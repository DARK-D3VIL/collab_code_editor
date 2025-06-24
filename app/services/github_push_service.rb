# app/services/github_push_service.rb
class GithubPushService
  def initialize(project, branch, user)
    @project = project
    @branch = branch
    @user = user
  end

  def call
    begin
      perform_push
      Result.new(success: true)
    rescue => e
      Rails.logger.error "GitHub push error: #{e.message}"
      Result.new(success: false, error: e.message)
    end
  end

  private

  def perform_push
    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")

    raise "Local git repository not found" unless Dir.exist?(repo_path.join(".git"))

    repo = Rugged::Repository.new(repo_path.to_s)
    setup_remote(repo)
    push_branch(repo)
  end

  def setup_remote(repo)
    github_url = @project.github_url
    match = github_url.match(/github\.com[\/:]([^\/]+)\/([^\/\.]+)/)

    raise "Invalid GitHub URL format" unless match

    owner, repo_name = match[1], match[2]
    token = @user.github_token
    authenticated_url = "https://#{token}:x-oauth-basic@github.com/#{owner}/#{repo_name}.git"

    begin
      repo.remotes.set_url("origin", authenticated_url)
    rescue Rugged::ConfigError
      repo.remotes.create("origin", authenticated_url)
    end
  end

  def push_branch(repo)
    branch_ref = "refs/heads/#{@branch.name}"
    remote = repo.remotes["origin"]

    credentials = Rugged::Credentials::UserPassword.new(
      username: @user.github_token,
      password: "x-oauth-basic"
    )

    Timeout.timeout(60) do # 1 minute timeout for push
      remote.push([ branch_ref ], credentials: credentials)
    end
  end

  # Simple result class
  class Result
    attr_reader :success, :error

    def initialize(success:, error: nil)
      @success = success
      @error = error
    end

    def success?
      @success
    end
  end
end
