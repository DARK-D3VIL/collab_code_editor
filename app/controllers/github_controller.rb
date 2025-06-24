class GithubController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project, only: [ :sync, :link_repository, :push_to_github, :unlink_repository ]
  before_action :authorize_project_access, only: [ :sync, :link_repository, :push_to_github, :unlink_repository ]
  before_action :authorize_writer!, only: [ :link_repository, :push_to_github, :unlink_repository ]

  # Cache expensive GitHub API calls
  GITHUB_CACHE_DURATION = 5.minutes

  def repos
    token = current_user.github_token
    unless token
      redirect_to root_path, alert: "GitHub authentication failed."
      return
    end

    # Cache GitHub repos to avoid repeated API calls
    cache_key = "github_repos_#{current_user.id}_#{Digest::MD5.hexdigest(token)}"
    @repos = Rails.cache.fetch(cache_key, expires_in: GITHUB_CACHE_DURATION) do
      fetch_github_repos(token)
    end

    if @repos.nil?
      redirect_to root_path, alert: "Failed to fetch GitHub repositories."
    end
  end

  def clone
    repo_name = params[:repo_name]
    clone_url = params[:clone_url]

    # Optimize project name check with exists? instead of loading records
    if current_user.owned_projects.where(name: repo_name).exists?
      redirect_to github_repos_path, alert: "You've already cloned this repository."
      return
    end

    # Process clone immediately using service
    service = RepositoryCloneService.new(current_user, repo_name, clone_url, true)
    result = service.call

    if result.success?
      redirect_to project_project_files_path(result.project),
                  notice: "Repository cloned successfully!"
    else
      redirect_to github_repos_path, alert: "Failed to clone repository: #{result.error}"
    end
  end

  def sync
    # Optimize queries with includes and select
    @current_branch = current_branch_for_project
    @github_connected = github_token_valid?
    @github_repos = []

    if @github_connected && @project.github_url.blank?
      # Use cached repos if available
      cache_key = "github_repos_#{current_user.id}"
      @github_repos = Rails.cache.fetch(cache_key, expires_in: GITHUB_CACHE_DURATION) do
        fetch_github_repos(current_user.github_token)
      end || []
    end
  end

  def link_repository
    github_url = params[:github_url]

    unless github_url.present?
      redirect_to github_project_sync_path(@project), alert: "Please select a repository."
      return
    end

    # Use update! with validation
    @project.update!(github_url: github_url)

    # Clear related caches
    clear_project_caches(@project)

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

    # Process push in background job
    current_branch = current_branch_for_project
    PushToGithubJob.perform_later(
      project_id: @project.id,
      branch_id: current_branch.id,
      user_id: current_user.id
    )

    redirect_to github_project_sync_path(@project),
                notice: "Push to GitHub started. You'll be notified when it's complete."
  end

  def unlink_repository
    @project.update!(github_url: nil)
    clear_project_caches(@project)
    redirect_to github_project_sync_path(@project), notice: "Repository unlinked successfully!"
  end

  def clone_public
    github_url = params[:github_url]

    unless valid_github_url?(github_url)
      redirect_to new_project_path, alert: "Please provide a valid GitHub repository URL."
      return
    end

    repo_name = extract_repo_name(github_url)
    unique_repo_name = generate_unique_repo_name(repo_name)

    # Process clone immediately using service
    service = RepositoryCloneService.new(current_user, unique_repo_name, github_url, false)
    result = service.call

    if result.success?
      redirect_to project_project_files_path(result.project),
                  notice: "Repository cloned successfully!"
    else
      redirect_to new_project_path, alert: "Failed to clone repository: #{result.error}"
    end
  end

  private

  def set_project
    # Optimize with select to avoid loading unnecessary columns
    @project = current_user.accessible_projects
                          .select(:id, :name, :slug, :github_url, :owner_id)
                          .find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: "Project not found."
  end

  def authorize_project_access
    # Use optimized query with joins instead of separate queries
    unless has_project_access?(@project)
      redirect_to projects_path, alert: "You are not authorized to access this project."
    end
  end

  def has_project_access?(project)
    return true if project.owner_id == current_user.id

    # Cache project membership check using the active_members scope
    cache_key = "project_access_#{current_user.id}_#{project.id}"
    Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      project.project_memberships.active_members.where(user_id: current_user.id).exists?
    end
  end

  def current_branch_for_project
    # Optimize with includes and caching
    cache_key = "current_branch_#{current_user.id}_#{@project.id}"
    Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
      membership = current_user.project_memberships
                             .includes(:current_branch)
                             .find_by(project_id: @project.id)

      membership&.current_branch || default_branch_for(@project)
    end
  end

  def default_branch_for(project)
    # Cache default branch lookup
    cache_key = "default_branch_#{project.id}"
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      project.branches.where(name: "main").first ||
      project.branches.order(:created_at).first
    end
  end

  def github_token_valid?
    return false unless current_user.github_token.present?

    # Cache token validation to avoid repeated API calls
    cache_key = "github_token_valid_#{current_user.id}_#{Digest::MD5.hexdigest(current_user.github_token)}"
    Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
      validate_github_token(current_user.github_token)
    end
  end

  def validate_github_token(token)
    begin
      response = faraday_connection.get("/user") do |req|
        req.headers["Authorization"] = "token #{token}"
        req.headers["Accept"] = "application/vnd.github+json"
        req.options.timeout = 10 # Add timeout
      end
      response.success?
    rescue Faraday::Error
      false
    end
  end

  def fetch_github_repos(token)
    begin
      response = faraday_connection.get("/user/repos") do |req|
        req.headers["Authorization"] = "token #{token}"
        req.headers["Accept"] = "application/vnd.github+json"
        req.params["per_page"] = 100 # Increase page size
        req.params["sort"] = "updated"
        req.options.timeout = 15
      end

      return JSON.parse(response.body) if response.success?
    rescue Faraday::Error => e
      Rails.logger.error "GitHub API error: #{e.message}"
    end
    nil
  end

  def faraday_connection
    @faraday_connection ||= Faraday.new(
      url: "https://api.github.com",
      request: { timeout: 15 }
    ) do |faraday|
      faraday.adapter Faraday.default_adapter
    end
  end

  def current_user_membership
    @current_user_membership ||= @project.project_memberships
                                        .select(:id, :user_id, :project_id, :active, :role)
                                        .find_by(user_id: current_user.id)
  end

  def authorize_writer!
    membership = current_user_membership
    unless @project.owner_id == current_user.id || (membership&.active? && membership&.can_write?)
      redirect_to project_project_files_path(@project),
                  alert: "You need writer permission to perform this action."
    end
  end

  def valid_github_url?(url)
    url.present? && url.match(/^https:\/\/github\.com\/[^\/]+\/[^\/]+/)
  end

  def extract_repo_name(github_url)
    match = github_url.match(/github\.com\/[^\/]+\/([^\/\.]+)/)
    match ? match[1] : "imported-project"
  end

  def generate_unique_repo_name(base_name)
    return base_name unless current_user.owned_projects.where(name: base_name).exists?

    counter = 1
    loop do
      candidate_name = "#{base_name}-#{counter}"
      break candidate_name unless current_user.owned_projects.where(name: candidate_name).exists?
      counter += 1
    end
  end

  def clear_project_caches(project)
    # Clear relevant caches when project is updated
    Rails.cache.delete("default_branch_#{project.id}")
    Rails.cache.delete("current_branch_#{current_user.id}_#{project.id}")
    Rails.cache.delete("project_access_#{current_user.id}_#{project.id}")
  end
end
