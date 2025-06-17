class ProjectsController < ApplicationController
  before_action :authenticate_user!

  def index
    @projects = current_user.accessible_projects
  end

  def new
    @project = Project.new
  end

  def create
    slug = SecureRandom.hex(3)
    @project = current_user.owned_projects.new(project_params.merge(slug: slug))
    if @project.save
      # 1. Create project directory
      repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
      FileUtils.mkdir_p(repo_path)

      # 2. Initialize Git repo
      repo = Rugged::Repository.init_at(repo_path.to_s)
      repo.config["user.name"] = current_user.username
      repo.config["user.email"] = current_user.email

      # 3. Create initial commit and main branch
      oid = repo.write("Initial README", :blob)  # Add some content
      index = repo.index
      index.add(path: "README.md", oid: oid, mode: 0o100644)
      tree_oid = index.write_tree(repo)

      author = {
        email: current_user.email,
        name: current_user.username,
        time: Time.now
      }

      commit_oid = Rugged::Commit.create(repo, {
        message: "Initial commit",
        author: author,
        committer: author,
        tree: tree_oid,
        parents: [],
        update_ref: "HEAD"
      })

      # Rename current branch to main
      repo.branches.create("main", commit_oid)
      repo.references.update("HEAD", "refs/heads/main")

      # 4. Create DB branch
      main_branch = @project.branches.create!(
        name: "main",
        created_by: current_user.id
      )

      # 5. Store commit in DB
      Commit.create!(
        user: current_user,
        branch: main_branch,
        project: @project,
        message: "Initial commit",
        sha: commit_oid,
        parent_sha: nil
      )

      # 6. Create membership and set current branch
      ProjectMembership.create!(
        user: current_user,
        project: @project,
        current_branch: main_branch
      )

      redirect_to project_project_files_path(@project), notice: "Project created successfully!"
    else
      render :new
    end
  end

  def show
    @project = Project.includes(project_memberships: :user).find(params[:id])

    # Allow access if current_user is the owner or an active member
    is_owner = @project.owner == current_user
    is_active_member = @project.project_memberships.exists?(user_id: current_user.id, active: true)

    unless is_owner || is_active_member
      redirect_to projects_path, alert: "You are not authorized to access this project."
      return
    end

    @active_members = @project.project_memberships
                              .includes(:user)
                              .where(active: true)
                              .map(&:user)
  end
  def join
    @project = Project.find_by(slug: params[:project_code])
    if @project.nil?
      redirect_to projects_path, alert: "Project not found with that code."
      return
    end

    # Check if user is already a member
    membership = @project.project_memberships.find_by(user: current_user)
    if membership&.active?
      redirect_to project_path(@project), notice: "You are already a member of this project."
      return
    elsif membership
      redirect_to projects_path, alert: "You have been removed from this project."
      return
    end

    # Check if user already has a pending request
    if @project.has_pending_request?(current_user)
      redirect_to projects_path, alert: "You already have a pending request for this project."
      return
    end

    # Create join request
    join_request = @project.project_join_requests.build(user: current_user)

    if join_request.save
      # Send email notification to project owner
      ProjectRequestMailerJob.perform_later(:new_join_request, @project.owner.id, @project.id, join_request.id)

      redirect_to projects_path, notice: "Join request sent to project owner. You'll be notified once approved."
    else
      redirect_to projects_path, alert: "Failed to send join request. Please try again."
    end
  end

  def destroy
    @project = Project.find(params[:id])

    unless @project.owner_id == current_user.id
      redirect_to projects_path, alert: "Only the owner can delete the project."
      return
    end

    # Delete associated records manually (if no `dependent: :destroy`)
    ConflictQueue.where(project_id: @project.id).destroy_all
    @project.project_memberships.destroy_all
    @project.branches.destroy_all
    @project.files.destroy_all

    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    FileUtils.rm_rf(repo_path) if Dir.exist?(repo_path)

    @project.destroy

    redirect_to projects_path, notice: "Project deleted successfully."
  end

  def upload
    uploaded_file = params[:zip_file]
    project_name = params[:project_name]

    unless uploaded_file.present?
      redirect_to new_project_path, alert: "Please select a zip file to upload."
      return
    end

    # Validate file type
    unless uploaded_file.original_filename.downcase.ends_with?(".zip")
      redirect_to new_project_path, alert: "Please upload a .zip file."
      return
    end

    # Validate file size (50MB limit)
    if uploaded_file.size > 50.megabytes
      redirect_to new_project_path, alert: "File size must be less than 50MB."
      return
    end

    begin
      # Create temporary directory for extraction
      temp_dir = Rails.root.join("tmp", "uploads", SecureRandom.hex(8))
      FileUtils.mkdir_p(temp_dir)

      # Save uploaded file temporarily
      temp_zip_path = temp_dir.join("upload.zip")
      File.open(temp_zip_path, "wb") do |file|
        file.write(uploaded_file.read)
      end

      # Extract zip file
      extract_dir = temp_dir.join("extracted")
      FileUtils.mkdir_p(extract_dir)

      system("unzip", "-q", temp_zip_path.to_s, "-d", extract_dir.to_s)

      unless $?.success?
        raise "Failed to extract zip file. Please ensure it's a valid zip archive."
      end

      # Find the root directory (in case everything is nested in a folder)
      extracted_contents = Dir.entries(extract_dir).reject { |entry| entry.start_with?(".") }

      if extracted_contents.size == 1 && File.directory?(extract_dir.join(extracted_contents.first))
        # Everything is in a single folder
        source_dir = extract_dir.join(extracted_contents.first)
        project_name = project_name.presence || extracted_contents.first
      else
        # Files are at root level
        source_dir = extract_dir
        project_name = project_name.presence || File.basename(uploaded_file.original_filename, ".zip")
      end

      # Ensure unique project name
      counter = 1
      original_name = project_name
      while current_user.owned_projects.exists?(name: project_name)
        project_name = "#{original_name}-#{counter}"
        counter += 1
      end

      # Create project
      slug = SecureRandom.hex(3)
      project = current_user.owned_projects.create!(
        name: project_name,
        slug: slug
      )

      # Create project directory
      repo_path = Rails.root.join("storage", "projects", "project_#{project.id}")
      FileUtils.mkdir_p(repo_path)

      # Check if this is a Git repository
      git_dir = source_dir.join(".git")

      if File.directory?(git_dir)
        # This is a Git repository - copy everything and process Git history
        FileUtils.cp_r(source_dir.to_s + "/.", repo_path.to_s)

        begin
          repo = Rugged::Repository.new(repo_path.to_s)

          # Process existing Git repository
          process_git_repository(repo, project, current_user)

          redirect_to project_project_files_path(project),
                      notice: "Successfully imported Git repository with history!"

        rescue => e
          Rails.logger.error "Error processing Git repository: #{e.message}"
          # Fall back to treating as regular files
          initialize_new_repository(source_dir, repo_path, project, current_user, project_name)

          redirect_to project_project_files_path(project),
                      notice: "Project uploaded successfully! (Git history could not be preserved)"
        end
      else
        # Regular file upload - initialize new Git repository
        initialize_new_repository(source_dir, repo_path, project, current_user, project_name)

        redirect_to project_project_files_path(project),
                    notice: "Project uploaded and initialized successfully!"
      end

    rescue => e
      # Clean up on error
      project&.destroy
      FileUtils.rm_rf(repo_path) if repo_path && Dir.exist?(repo_path)
      Rails.logger.error "Upload error: #{e.message}\n#{e.backtrace.join("\n")}"
      redirect_to new_project_path, alert: "Failed to process upload: #{e.message}"

    ensure
      # Clean up temporary files
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end
  end

  private

  # Process existing Git repository from uploaded zip
  def process_git_repository(repo, project, user)
    return if repo.empty?

    # Get all branches
    branches = {}
    default_branch = nil

    # Process local branches
    repo.branches.each_name(:local) do |branch_name|
      branch_obj = repo.branches[branch_name]
      next unless branch_obj

      db_branch = project.branches.create!(
        name: branch_name,
        created_by: user.id
      )

      branches[branch_name] = db_branch

      # Set default branch (prefer main, then master, then first)
      if branch_name == "main" || (default_branch.nil? && branch_name == "master") || default_branch.nil?
        default_branch = db_branch
      end
    end

    # Process commits for each branch
    total_commits = 0
    branches.each do |branch_name, db_branch|
      begin
        branch_ref = repo.branches[branch_name]
        next unless branch_ref

        walker = Rugged::Walker.new(repo)
        walker.push(branch_ref.target_id)

        commit_count = 0
        walker.each do |commit|
          # Skip if commit already processed (shared history)
          next if Commit.exists?(project: project, sha: commit.oid)

          Commit.create!(
            user: user,
            branch: db_branch,
            project: project,
            message: commit.message,
            sha: commit.oid,
            parent_sha: commit.parents.first&.oid
          )

          commit_count += 1
          total_commits += 1

          # Limit to prevent timeout
          break if commit_count >= 1000
        end

        walker.reset
      rescue => e
        Rails.logger.error "Error processing branch #{branch_name}: #{e.message}"
      end
    end

    # Create project membership
    ProjectMembership.create!(
      user: user,
      project: project,
      current_branch: default_branch
    )

    Rails.logger.info "Processed Git repository: #{total_commits} commits across #{branches.size} branches"
  end

  # Initialize new Git repository from uploaded files
  def initialize_new_repository(source_dir, repo_path, project, user, project_name)
    # Copy all files except .git directory
    Dir.glob("#{source_dir}/**/*", File::FNM_DOTMATCH).each do |source_file|
      next if File.basename(source_file).start_with?(".git")
      next if File.directory?(source_file)

      relative_path = Pathname.new(source_file).relative_path_from(Pathname.new(source_dir.to_s))
      dest_file = repo_path.join(relative_path)

      FileUtils.mkdir_p(File.dirname(dest_file))
      FileUtils.cp(source_file, dest_file)
    end

    # Initialize new Git repository
    repo = Rugged::Repository.init_at(repo_path.to_s)
    repo.config["user.name"] = user.username
    repo.config["user.email"] = user.email

    # Add all files to the repository
    index = repo.index

    Dir.glob("#{repo_path}/**/*").each do |file_path|
      next if File.directory?(file_path)

      relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(repo_path.to_s))
      next if relative_path.to_s.start_with?(".git/")

      # Read file content and add to index
      content = File.read(file_path)
      oid = repo.write(content, :blob)
      index.add(path: relative_path.to_s, oid: oid, mode: 0o100644)
    end

    # Create initial commit if there are files
    if index.count > 0
      tree_oid = index.write_tree(repo)

      author = {
        email: user.email,
        name: user.username,
        time: Time.now
      }

      commit_oid = Rugged::Commit.create(repo, {
        message: "Initial commit from uploaded files",
        author: author,
        committer: author,
        tree: tree_oid,
        parents: [],
        update_ref: "HEAD"
      })

      # Create main branch
      repo.branches.create("main", commit_oid)
      repo.references.update("HEAD", "refs/heads/main")

      # Create DB records
      main_branch = project.branches.create!(
        name: "main",
        created_by: user.id
      )

      Commit.create!(
        user: user,
        branch: main_branch,
        project: project,
        message: "Initial commit from uploaded files",
        sha: commit_oid,
        parent_sha: nil
      )

      # Create membership
      ProjectMembership.create!(
        user: user,
        project: project,
        current_branch: main_branch
      )
    else
      # No files found, create empty repository
      raise "No files found in the uploaded archive"
    end
  end

  def project_params
    params.require(:project).permit(:name)
  end
end
