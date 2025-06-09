class ProjectFilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :authorize_user!
  before_action :set_path_vars, only: [ :index, :create_folder ]
  before_action :switch_to_user_branch

  def index
    @project = current_user.projects.find(params[:project_id])

    @repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    @current_path = Pathname.new(params[:path].to_s).cleanpath.to_s
    @absolute_path = @repo_path.join(@current_path)

    unless @absolute_path.to_s.start_with?(@repo_path.to_s) && @absolute_path.exist?
      redirect_to project_project_files_path(@project), alert: "Invalid folder path" and return
    end

    entries = FileBrowserService.new(@absolute_path).list_entries
    @folders = entries.select { |entry| File.directory?(@absolute_path.join(entry)) }
    @files   = entries.select   { |entry| File.file?(@absolute_path.join(entry)) }

    @project_repo_path = @repo_path
  end

  def new
    @file = ProjectFile.new
  end

  def edit
    @project = current_user.projects.find(params[:project_id])
    @current_path = params[:path].to_s
    file_name = params[:id]

    @file = @project.files.find_by(name: file_name, path: @current_path)
    unless @file
      redirect_to project_project_files_path(@project, path: @current_path), alert: "File not found." and return
    end

    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    full_path = repo_path.join(@current_path, @file.name)
    unless File.exist?(full_path)
      redirect_to project_project_files_path(@project, path: @current_path), alert: "File does not exist in storage." and return
    end

    @file_content = File.read(full_path)
    @branch_name = current_branch_for_project.name

    # Use stored language from DB and map to Monaco expected
    @language = {
      "rb" => "ruby",
      "js" => "javascript",
      "html" => "html",
      "css" => "css",
      "json" => "json",
      "py" => "python",
      "java" => "java",
      "md" => "markdown"
    }[@file.language] || "plaintext"
  end


  def save
    @project = current_user.projects.find(params[:project_id])
    @file = @project.files.find(params[:id])
    @path = params[:path]

    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    file_path = repo_path.join(@path, @file.name)

    if File.exist?(file_path)
      File.write(file_path, params[:content])
      respond_to do |format|
        format.json { render json: { status: "success" } }
        format.html { redirect_to project_project_files_path(@project, path: @path), notice: "File saved." }
      end
    else
      respond_to do |format|
        format.json { render json: { status: "error", message: "File not found." }, status: :not_found }
        format.html { redirect_to project_project_files_path(@project, path: @path), alert: "File not found." }
      end
    end
  end

  def create
    result = FileCreationService.new(@project, file_params).call

    if result.success?
      redirect_to project_project_files_path(@project, path: file_params[:path]), notice: "File created!"
    else
      redirect_to new_project_project_file_path(@project), alert: result.error
    end
  end

  def create_folder
    result = FolderCreationService.new(@repo_path, params[:folder_name]).call

    if result.success?
      redirect_to project_project_files_path(@project, path: @current_path), notice: "Folder created."
    else
      redirect_to project_project_files_path(@project, path: @current_path), alert: result.error
    end
  end

  def commit
    @path = params[:path]
    commit_message = params[:message]

    repo_path = project_repo_path
    commit_sha = nil

    Dir.chdir(repo_path) do
      repo = Rugged::Repository.new(repo_path)

      # Stage changes
      index = repo.index
      index.reload
      index.add_all(@path)
      index.write
      tree_oid = index.write_tree(repo)

      # Get the current branch ref and parent commit
      branch = current_branch_for_project.name
      branch_ref = "refs/heads/#{branch}"
      parent_commit = repo.empty? ? [] : [repo.head.target]

      author = {
        email: current_user.email,
        name: current_user.username.presence || current_user.email.split('@').first,
        time: Time.now
      }

      # Create commit
      commit_sha = Rugged::Commit.create(repo,
        author: author,
        committer: author,
        message: commit_message,
        parents: parent_commit,
        tree: tree_oid,
        update_ref: branch_ref
      )

      # Save commit in DB
      Commit.create!(
        user_id: current_user.id,
        project_id: @project.id,
        branch_id: current_branch_for_project.id,
        message: commit_message,
        sha: commit_sha,
        parent_sha: parent_commit.first&.oid
      )
    end

    render json: { status: "success", sha: commit_sha }
  rescue => e
    render json: { status: "error", message: "Commit failed: #{e.message}" }, status: 500
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_user!
    unless @project.users.include?(current_user) || @project.owner == current_user
      redirect_to project_projects_path, alert: "You are not authorized to access this project."
    end
  end

  def set_path_vars
    @current_path = params[:path].to_s
    @repo_path = project_repo_path.join(@current_path)
  end

  def project_repo_path
    Rails.root.join("storage", "projects", "project_#{@project.id}")
  end

  def file_params
    params.require(:file).permit(:name, :language, :content, :path)
  end

  def switch_to_user_branch
    repo_path = project_repo_path
    branch = current_branch_for_project

    return unless branch.present?

    Dir.chdir(repo_path) do
      current = `git rev-parse --abbrev-ref HEAD`.strip
      if current != branch
        `git fetch`
        system("git checkout #{branch}") || raise("Failed to switch to branch: #{branch}")
      end
    end
  rescue => e
    redirect_to project_projects_path, alert: "Git error: #{e.message}"
  end

  def current_branch_for_project
    current_user.current_branch_for(@project) || default_branch_for(@project)
  end

  def default_branch_for(project)
    project.branches.find_by(name: "main") || project.branches.first
  end

  def latest_commit_sha
    Commit.where(branch_id: current_branch).order(created_at: :desc).limit(1).pluck(:sha).first
  end
end
