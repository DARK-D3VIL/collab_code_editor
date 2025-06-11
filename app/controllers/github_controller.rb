class GithubController < ApplicationController
  before_action :authenticate_user!

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

    # Create new Project
    slug = SecureRandom.hex(3)
    project = current_user.owned_projects.create!(
      name: repo_name,
      slug: slug
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
end
