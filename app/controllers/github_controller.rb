class GithubController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project, only: [ :sync, :link_repository, :push_to_github, :unlink_repository ]
  before_action :authorize_project_access, only: [ :sync, :link_repository, :push_to_github, :unlink_repository ]
  before_action :authorize_writer!, only: [ :link_repository, :push_to_github, :unlink_repository ]
  def repos
    token = current_user.github_token
    unless token
      redirect_to root_path, alert: "GitHub authentication failed."
      return
    end

    response = Faraday.get("https://api.github.com/user/repos", {}, {
      Authorization: "token #{token}",
      Accept: "application/vnd.github+json"
    })

    @repos = JSON.parse(response.body)
  end

  def clone
    repo_name = params[:repo_name]
    clone_url = params[:clone_url]

    # Check if the user already has a project with this repo name
    if current_user.owned_projects.exists?(name: repo_name)
      redirect_to github_repos_path, alert: "You've already cloned this repository."
      return
    end

    # Create new Project
    slug = SecureRandom.hex(3)
    project = current_user.owned_projects.create!(
      name: repo_name,
      slug: slug,
      github_url: clone_url
    )

    repo_path = Rails.root.join("storage", "projects", "project_#{project.id}")
    FileUtils.mkdir_p(repo_path)

    # Clone the repo into that path
    Rugged::Repository.clone_at(clone_url, repo_path.to_s)

    # Read the repo and fetch metadata from it
    repo = Rugged::Repository.new(repo_path.to_s)
    head = repo.head.target_id
    branch_name = repo.head.name.sub("refs/heads/", "")

    branch = project.branches.create!(
      name: branch_name,
      created_by: current_user.id
    )

    walker = Rugged::Walker.new(repo)
    walker.push(head)
    walker.each do |commit|
      Commit.create!(
        user: current_user,
        branch: branch,
        project: project,
        message: commit.message,
        sha: commit.oid,
        parent_sha: commit.parents.first&.oid
      )
    end

    ProjectMembership.create!(
      user: current_user,
      project: project,
      current_branch: branch
    )

    redirect_to project_project_files_path(project), notice: "Cloned project successfully!"
  end

  # New method for the unified sync page
  def sync
    @current_branch = current_branch_for_project
    @github_connected = github_token_valid?
    @github_repos = []

    if @github_connected && @project.github_url.blank?
      # Fetch user's GitHub repositories
      token = current_user.github_token
      begin
        response = Faraday.get("https://api.github.com/user/repos", {}, {
          Authorization: "token #{token}",
          Accept: "application/vnd.github+json"
        })
        @github_repos = JSON.parse(response.body) if response.success?
      rescue => e
        Rails.logger.error "Failed to fetch GitHub repos: #{e.message}"
        @github_connected = false
      end
    end
  end

  def link_repository
    github_url = params[:github_url]

    unless github_url.present?
      redirect_to github_project_sync_path(@project), alert: "Please select a repository."
      return
    end

    @project.update!(github_url: github_url)
    redirect_to github_project_sync_path(@project), notice: "Repository linked successfully!"
  end

  def push_to_github
    unless @project.github_url.present?
      redirect_to github_project_sync_path(@project), alert: "No GitHub repository linked."
      return
    end

    unless github_token_valid?
      redirect_to github_project_sync_path(@project), alert: "GitHub authentication required."
      return
    end

    current_branch = current_branch_for_project
    result = push_project_to_github(@project, current_branch)

    if result[:success]
      redirect_to github_project_sync_path(@project), notice: "Code pushed to GitHub successfully!"
    else
      redirect_to github_project_sync_path(@project), alert: "Failed to push to GitHub: #{result[:error]}"
    end
  end

  def unlink_repository
    @project.update!(github_url: nil)
    redirect_to github_project_sync_path(@project), notice: "Repository unlinked successfully!"
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_project_access
    membership = @project.project_memberships.find_by(user_id: current_user.id)
    unless @project.owner == current_user || (membership&.active?)
      redirect_to projects_path, alert: "You are not authorized to access this project."
    end
  end

  def current_branch_for_project
    current_user.current_branch_for(@project) || default_branch_for(@project)
  end

  def default_branch_for(project)
    project.branches.find_by(name: "main") || project.branches.first
  end

  def github_token_valid?
    return false unless current_user.github_token.present?

    # Test the token by making a simple API call
    begin
      response = Faraday.get("https://api.github.com/user", {}, {
        Authorization: "token #{current_user.github_token}",
        Accept: "application/vnd.github+json"
      })
      response.success?
    rescue
      false
    end
  end

  def current_membership
    @current_membership ||= current_user.project_memberships.find_by(project_id: @project.id)
  end

  def push_project_to_github(project, branch)
    begin
      repo_path = Rails.root.join("storage", "projects", "project_#{project.id}")

      unless Dir.exist?(repo_path.join(".git"))
        return { success: false, error: "Local git repository not found" }
      end

      repo = Rugged::Repository.new(repo_path.to_s)

      # Parse GitHub URL to get owner and repo name
      github_url = project.github_url
      match = github_url.match(/github\.com[\/:]([^\/]+)\/([^\/\.]+)/)

      unless match
        return { success: false, error: "Invalid GitHub URL format" }
      end

      owner, repo_name = match[1], match[2]

      # Set up remote with authentication
      token = current_user.github_token
      authenticated_url = "https://#{token}:x-oauth-basic@github.com/#{owner}/#{repo_name}.git"

      # Check if remote exists, if not create it
      begin
        remote = repo.remotes["origin"]
      rescue Rugged::ConfigError
        remote = repo.remotes.create("origin", authenticated_url)
      end

      # Update remote URL with token
      repo.remotes.set_url("origin", authenticated_url)

      # Push current branch
      branch_ref = "refs/heads/#{branch.name}"

      begin
        remote = repo.remotes["origin"]

        # Fix: Correct credentials format for Rugged
        credentials = Rugged::Credentials::UserPassword.new(
          username: token,
          password: "x-oauth-basic"
        )

        # Push with correct syntax
        remote.push([ branch_ref ], credentials: credentials)

        { success: true }
      rescue Rugged::NetworkError => e
        { success: false, error: "Network error: #{e.message}" }
      rescue Rugged::ReferenceError => e
        { success: false, error: "Reference error: #{e.message}" }
      end

    rescue => e
      Rails.logger.error "GitHub push error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  def authorize_writer!
    membership = current_user_membership
    unless @project.owner == current_user || (membership&.active? && membership&.can_write?)
      redirect_to project_project_files_path(@project), alert: "You need writer permission to perform this action."
    end
  end
  def current_user_membership
    @current_user_membership ||= @project.project_memberships.find_by(user_id: current_user.id)
  end
end
