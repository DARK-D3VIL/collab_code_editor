# app/services/repository_clone_service.rb
class RepositoryCloneService
  def initialize(user, repo_name, clone_url, is_authenticated)
    @user = user
    @repo_name = repo_name
    @clone_url = clone_url
    @is_authenticated = is_authenticated
  end

  def call
    ActiveRecord::Base.transaction do
      create_project_and_clone
    end
  rescue => e
    cleanup_on_error
    Result.new(success: false, error: e.message)
  end

  private

  def create_project_and_clone
    @project = @user.owned_projects.create!(
      name: @repo_name,
      slug: SecureRandom.hex(3),
      github_url: @clone_url
    )

    clone_repository
    process_repository_data
    create_project_membership

    Result.new(success: true, project: @project)
  end

  def clone_repository
    @repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    FileUtils.mkdir_p(@repo_path)

    # Add timeout and retry logic
    Timeout.timeout(300) do # 5 minute timeout
      Rugged::Repository.clone_at(@clone_url, @repo_path.to_s)
    end
  end

  def process_repository_data
    repo = Rugged::Repository.new(@repo_path.to_s)

    raise "Cannot clone empty repository" if repo.empty?

    # Process branches and commits in batches
    process_branches_and_commits(repo)
  end

  def process_branches_and_commits(repo)
    created_branches = {}
    default_branch = nil

    # Create branches in batch
    branches_data = repo.branches.each_name(:local).map do |branch_name|
      {
        name: branch_name,
        created_by: @user.id,
        project_id: @project.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    Branch.insert_all(branches_data) if branches_data.any?

    # Reload branches and process commits
    @project.branches.each do |branch|
      created_branches[branch.name] = branch
      default_branch ||= branch if [ "main", "master" ].include?(branch.name)
    end

    default_branch ||= created_branches.values.first

    # Process commits for each branch in batches
    process_commits_for_branches(repo, created_branches)

    @default_branch = default_branch
  end

  def process_commits_for_branches(repo, created_branches)
    created_branches.each do |branch_name, db_branch|
      begin
        branch_ref = repo.branches[branch_name]
        next unless branch_ref

        commits_data = []
        walker = Rugged::Walker.new(repo)
        walker.push(branch_ref.target_id)

        walker.each_with_index do |commit, index|
          break if index >= 1000 # Limit commits

          commits_data << {
            user_id: @user.id,
            branch_id: db_branch.id,
            project_id: @project.id,
            message: commit.message,
            sha: commit.oid,
            parent_sha: commit.parents.first&.oid,
            created_at: Time.current,
            updated_at: Time.current
          }

          # Insert in batches of 100
          if commits_data.size >= 100
            Commit.insert_all(commits_data, unique_by: [ :project_id, :sha ])
            commits_data.clear
          end
        end

        # Insert remaining commits
        if commits_data.any?
          Commit.insert_all(commits_data, unique_by: [ :project_id, :sha ])
        end

        walker.reset
      rescue => e
        Rails.logger.error "Error processing branch #{branch_name}: #{e.message}"
      end
    end
  end

  def create_project_membership
    ProjectMembership.create!(
      user: @user,
      project: @project,
      current_branch: @default_branch
    )
  end

  def cleanup_on_error
    @project&.destroy
    FileUtils.rm_rf(@repo_path) if @repo_path && Dir.exist?(@repo_path)
  end

  # Simple result class
  class Result
    attr_reader :success, :error, :project

    def initialize(success:, error: nil, project: nil)
      @success = success
      @error = error
      @project = project
    end

    def success?
      @success
    end
  end
end
