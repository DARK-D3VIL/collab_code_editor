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

    membership = @project.project_memberships.find_by(user: current_user)
    if membership&.active?
      redirect_to project_path(@project), notice: "You are already a member of this project."
    elsif membership
      redirect_to projects_path, alert: "You have been removed from this project."
    else
      main_branch = @project.branches.find_by(name: "main")
      ProjectMembership.create!(
        user: current_user,
        project: @project,
        current_branch: main_branch
      )
      redirect_to project_project_files_path(@project), notice: "Successfully joined the project."
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

  private

  def project_params
    params.require(:project).permit(:name)
  end
end
