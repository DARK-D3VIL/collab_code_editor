class ProjectsController < ApplicationController
  before_action :authenticate_user!

  def index
    @projects = current_user.projects
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

      redirect_to @project, notice: "Project created successfully!"
    else
      render :new
    end
  end

  def show
    @project = Project.find(params[:id])
    unless @project.users.include?(current_user) || @project.owner == current_user
      redirect_to projects_path, alert: "You are not authorized to access this project."
    end
  end

  def join
    project = Project.find_by(slug: params[:project_code])

    if project.nil?
      redirect_to projects_path, alert: "Project not found with that code."
      return
    end

    if project.users.include?(current_user)
      redirect_to project_path(project), notice: "You are already a member of this project."
      return
    end

    main_branch = project.branches.find_by(name: "main")

    ProjectMembership.create!(
      user: current_user,
      project: project,
      current_branch: main_branch
    )

    redirect_to project_path(project), notice: "Successfully joined the project."
  end

  private

  def project_params
    params.require(:project).permit(:name)
  end
end
