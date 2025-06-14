include ProjectFilesHelper

class ProjectFilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :authorize_user!
  before_action :set_path_vars, only: [ :index, :create_folder ]
  before_action :authorize_writer!, only: [ :save, :create, :create_folder, :commit, :commit_all, :destroy_file, :destroy_folder, :new ]
  before_action :switch_to_user_branch, except: [ :destroy_file, :destroy_folder ] # Exclude delete actions

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

    entries = FileBrowserService.new(@absolute_path).list_entries.reject do |entry|
      entry.end_with?(".deleted")
    end

    @files = entries.select do |entry|
      file_path = @absolute_path.join(entry)
      File.file?(file_path)
    end

    @folders = entries.select do |entry|
      folder_path = @absolute_path.join(entry)
      File.directory?(folder_path)
    end

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
    @can_edit = current_user_membership&.can_write? || @project.owner == current_user
    unless editable_file?(@file_name)
      redirect_to project_project_files_path(@project, path: @current_path), alert: "This file type is not supported for editing." and return
    end

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

    @language = language_for_extension(@file_name)
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
      # Actually delete the file and create marker for git tracking
      FileUtils.rm_f(abs_path)
      File.write("#{abs_path}.deleted", "")
      flash[:notice] = "File deleted successfully."
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
      # Actually delete the folder and create marker for git tracking
      FileUtils.rm_rf(abs_path)
      File.write("#{abs_path}.deleted", "")
      flash[:notice] = "Folder deleted successfully."
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
    membership = @project.project_memberships.find_by(user_id: current_user.id)
    unless @project.owner == current_user || (membership&.active?)
      redirect_to projects_path, alert: "You are not authorized to access this project."
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

    # Check if we're already on the correct branch
    current_branch_name = repo.head.name.sub("refs/heads/", "") rescue "main"
    return if current_branch_name == branch.name

    rugged_branch = repo.branches[branch.name]
    raise "Branch '#{branch.name}' not found" unless rugged_branch

    # Use safe checkout strategy instead of force
    repo.checkout(rugged_branch.name, strategy: :safe)
  rescue Rugged::CheckoutConflictError
    # Handle conflicts by using force checkout but preserve unsaved files
    preserve_working_changes(repo_path)
    repo.checkout(rugged_branch.name, strategy: :force)
    restore_working_changes(repo_path)
  rescue => e
    redirect_to project_projects_path, alert: "Git error: #{e.message}"
  end

  def preserve_working_changes(repo_path)
    @preserved_changes = {}

    Dir.glob("#{repo_path}/**/*.unsaved").each do |unsaved_file|
      relative_path = Pathname.new(unsaved_file).relative_path_from(Pathname.new(repo_path.to_s))
      @preserved_changes[relative_path.to_s] = File.read(unsaved_file)
    end
  end

  def restore_working_changes(repo_path)
    return unless @preserved_changes

    @preserved_changes.each do |relative_path, content|
      full_path = File.join(repo_path, relative_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end
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

      # Handle both specific path and all changes
      if path.present?
        index.add_all(path)
      else
        index.add_all
        # Also remove deleted files from index
        index.remove_all do |path_spec, matched_pathspecs|
          !File.exist?(File.join(repo_path, path_spec))
        end
      end

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

    # Restore unsaved files
    Dir.glob("#{base_dir}/**/*.unsaved").each do |unsaved_path|
      original_path = unsaved_path.sub(/\.unsaved$/, "")
      if File.exist?(original_path)
        File.write(original_path, File.read(unsaved_path))
        File.delete(unsaved_path)
      end
    end

    # Clean up deletion markers (files are already deleted)
    Dir.glob("#{base_dir}/**/*.deleted").each do |marker_path|
      File.delete(marker_path) if File.exist?(marker_path)
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

  def authorize_writer!
    membership = current_user_membership
    unless @project.owner == current_user || (membership&.active? && membership&.can_write?)
      redirect_to project_project_files_path(@project), alert: "You need writer permission to perform this action."
    end
  end

  # NEW: Helper method to get current user's membership
  def current_user_membership
    @current_user_membership ||= @project.project_memberships.find_by(user_id: current_user.id)
  end
end
