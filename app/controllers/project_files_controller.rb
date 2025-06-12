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

    @has_changes = Dir.chdir(project_repo_path) do
      `git status --porcelain`.present?
    end

    entries = FileBrowserService.new(@absolute_path).list_entries
    @folders = entries.select { |entry| File.directory?(@absolute_path.join(entry)) }
    @files   = entries.select   { |entry| File.file?(@absolute_path.join(entry)) }

    @project_repo_path = @repo_path
    @current_branch = current_branch_for_project&.name || "main"
  end

  def new
    @file = ProjectFile.new
  end

  def edit
    cookies.encrypted[:user_id] = current_user.id
    @project = current_user.projects.find(params[:project_id])
    @current_path = params[:path].to_s
    @file_name = params[:id]

    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    full_path = repo_path.join(@current_path, @file_name)

    unless File.exist?(full_path)
      redirect_to project_project_files_path(@project, path: @current_path), alert: "File not found." and return
    end

    unsaved_path = "#{full_path}.unsaved"
  @file_content = if File.exist?(unsaved_path)
                    File.read(unsaved_path)
  else
    File.read(full_path)
  end

    @branch_name = current_branch_for_project.name

    ext = File.extname(@file_name).delete(".")
    @language = {
      "rb" => "ruby",
      "js" => "javascript",
      "html" => "html",
      "css" => "css",
      "json" => "json",
      "py" => "python",
      "java" => "java",
      "md" => "markdown"
    }[ext] || "plaintext"
  end

  def save
    @project = current_user.projects.find(params[:project_id])

    # Safely build relative path
    relative_path = params[:path].present? ? File.join(params[:path], params[:id]) : params[:id]
    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    file_path = repo_path.join(relative_path)
    # For redirecting UI
    @path = params[:path].to_s

    if File.exist?(file_path)
      decoded_content = CGI.unescapeHTML(params[:content])
      File.write(file_path, decoded_content)
      File.write("#{file_path}.unsaved", decoded_content)

      ClearConflictQueueJob.perform_later(
        project_id: @project.id,
        user_id: current_user.id,
        branch: current_branch_for_project.name,
        path: @path
      )
      render json: { status: "success" } and return
    else
      render json: { status: "error", message: "File not found." }, status: :not_found and return
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

    commit_sha = commit_changes(path: @path, message: commit_message)
    ClearConflictQueueJob.perform_later(
        project_id: @project.id,
        user_id: current_user.id,
        branch: current_branch_for_project.name,
        path: @path
      )
    render json: { status: "success", sha: commit_sha }

  rescue => e
    render json: { status: "error", message: "Commit failed: #{e.message}" }, status: 500
  end

  def commit_all
    message = params[:message]

    commit_sha = commit_changes(message: message)
    render json: { status: "success", sha: commit_sha }

  rescue => e
    render json: { status: "error", message: "Commit failed: #{e.message}" }, status: 500
  end

  def destroy_file
    file = params[:file]
    path = params[:path]
    abs_path = project_repo_path.join(path, file)

    if File.exist?(abs_path)
      File.delete(abs_path)
      # @project.files.where(name: file, path: path).destroy_all
      sha = commit_changes(path: path, message: "Deleted #{file}")
      flash[:notice] = sha ? "File deleted and committed." : "File deleted, but commit failed."
    else
      flash[:alert] = "File not found."
    end

    redirect_to project_project_files_path(@project, path: path)
  end

  def destroy_folder
    folder = params[:folder]
    path = params[:path]
    abs_path = project_repo_path.join(path, folder)

    if abs_path.exist? && abs_path.directory?
      FileUtils.rm_rf(abs_path)
      @project.files.where("path LIKE ?", "#{File.join(path, folder)}%").destroy_all
      sha = commit_changes(path: path, message: "Deleted #{folder}")
      flash[:notice] = sha ? "Folder deleted and committed." : "Folder deleted, but commit failed."
    else
      flash[:alert] = "Folder not found."
    end

    redirect_to project_project_files_path(@project, path: path)
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

    repo = Rugged::Repository.new(repo_path.to_s)

    rugged_branch = repo.branches[branch.name]
    raise "Branch '#{branch.name}' not found" unless rugged_branch

    repo.checkout(rugged_branch.name, strategy: :force)
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

  def commit_changes(path: nil, message:)
    repo_path = project_repo_path
    commit_sha = nil

    Dir.chdir(repo_path) do
      # Step 1: Restore any unsaved files
      restore_unsaved_files!(repo_path, path)

      repo = Rugged::Repository.new(repo_path)

      index = repo.index
      index.reload
      path.present? ? index.add_all(path) : index.add_all
      index.write
      tree_oid = index.write_tree(repo)

      branch = current_branch_for_project.name
      branch_ref = "refs/heads/#{branch}"
      repo.checkout(branch_ref)

      parent_commit = repo.empty? ? [] : [ repo.head.target ]

      author = {
        email: current_user.email,
        name: current_user.username.presence || current_user.email.split("@").first,
        time: Time.now
      }

      commit_sha = Rugged::Commit.create(repo,
        author: author,
        committer: author,
        message: message,
        parents: parent_commit,
        tree: tree_oid,
        update_ref: branch_ref
      )

      Commit.create!(
        user_id: current_user.id,
        project_id: @project.id,
        branch_id: current_branch_for_project.id,
        message: message,
        sha: commit_sha,
        parent_sha: parent_commit.first&.oid
      )
    end

    commit_sha
  rescue => e
    Rails.logger.error("Commit failed: #{e.message}")
    raise e
  end

  def restore_unsaved_files!(repo_path, relative_path = nil)
    base_dir = relative_path.present? ? File.join(repo_path, relative_path) : repo_path

    Dir.glob("#{base_dir}/**/*.unsaved").each do |unsaved_path|
      original_path = unsaved_path.sub(/\.unsaved$/, "")

      # Only restore if the original exists (or optionally, always create it)
      if File.exist?(original_path)
        File.write(original_path, File.read(unsaved_path))
        File.delete(unsaved_path)
      end
    end
  end

  def time_ago_in_words(time)
    seconds = Time.current - time
    case seconds
    when 0..59
      "#{seconds.to_i} seconds ago"
    when 60..3599
      "#{(seconds / 60).to_i} minutes ago"
    when 3600..86399
      "#{(seconds / 3600).to_i} hours ago"
    else
      "#{(seconds / 86400).to_i} days ago"
    end
  end
end
