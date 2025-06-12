class ProjectGitController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :authorize_user!
  before_action :set_repo
  before_action :set_git_service

  def index
    @branches = @project.branches.order(:created_at)
    @selected_branch = current_membership.current_branch || @project.branches.find_by(name: "main")
    @commits = @git_service.commits_for_branch(@selected_branch.name)
  end

  def branches
    @branches = @project.branches.includes(:commits).order(:created_at)
    @current_branch = current_branch_for_project.name
  end

  def create_branch
    name = params[:name]
    from_branch = current_membership.current_branch || @project.branches.find_by(name: "main")
    base_sha = @git_service.current_commit_sha(from_branch.name)

    result = @git_service.create_branch(name, base_sha, current_user.id)

    if result.success?
      redirect_to project_git_branches_path(@project), notice: result.message
    else
      redirect_to project_git_branches_path(@project), alert: result.message
    end
  end


  def switch
    branch = @project.branches.find(params[:id])
    current_membership.update!(current_branch: branch)
    redirect_to project_project_files_path(@project), notice: "Switched to branch #{branch.name}"
  end

  def commits
    @branch = @project.branches.find_by(id: params[:id]) || @project.branches.find_by!(name: params[:id])
    @commits = @git_service.commits_for_branch(@branch.name)
  end

  def commit_diff
    @diff = @git_service.commit_diff(params[:sha])
  end

  # def rollback
  #   sha = params[:sha]
  #   @git_service.rollback_to_commit(sha)
  #   redirect_to project_git_branch_commits_path(@project, params[:id]), notice: "Rolled back to commit #{sha[0..6]}"
  # end

  def rollback
    sha = params[:sha]
    result = @git_service.rollback_to_commit(sha)

    if result[:success]
      redirect_to project_git_branch_commits_path(@project, params[:id]), notice: "Reverted commit #{sha[0..6]}"
    elsif result[:conflict]
      redirect_to project_git_branch_commits_path(@project, params[:id]), alert: "Conflict occurred during revert. Resolve manually."
    else
      redirect_to project_git_branch_commits_path(@project, params[:id]), alert: "Revert failed."
    end
  end



  def merge
    source_branch = @project.branches.find(params[:id])
    result = @git_service.merge_branch(source_branch.name, "main", author: git_author_hash)

    if result[:success]
      redirect_to project_git_branches_path(@project), notice: "Merged successfully. Commit: #{result[:sha]}"
    elsif result[:conflict]
      redirect_to project_git_branches_path(@project), alert: "Merge conflict occurred. Please resolve manually."
    else
      redirect_to project_git_branches_path(@project), alert: "Merge failed."
    end
  end

  def show
    @branches = @project.branches.pluck(:name)  # Ensure this is set properly
    puts @branches

    @graph_commits = []
    repo = @repo

    return if @branches.blank? || !repo  # Prevent further processing if no branches or repo is nil

    walker = Rugged::Walker.new(repo)

    @branches.each do |branch_name|
      next unless repo.branches.exist?(branch_name)

      walker.reset
      walker.push(repo.branches[branch_name].target_id)
      walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE)

      walker.each do |commit|
        @graph_commits << {
          sha: commit.oid,
          message: commit.message.lines.first.chomp,
          author: commit.author[:name],
          time: commit.time,
          branch: branch_name,
          parents: commit.parent_ids
        }
      end
    end

    @graph_commits.uniq! { |c| c[:sha] }
    @graph_commits = @graph_commits.sort_by { |c| c[:time] }
    puts @graph_commits
  end


  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_repo
    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    if Dir.exist?(repo_path.join(".git"))
      @repo = Rugged::Repository.new(repo_path.to_s)
    else
      redirect_to project_project_files_path(@project), alert: "Git repository not initialized." and return
    end
  end

  def set_git_service
    @git_service = GitService.new(@project)
  end

  def current_membership
    current_user.project_memberships.find_by(project_id: @project.id)
  end

  def current_branch_for_project
    current_user.current_branch_for(@project) || default_branch_for(@project)
  end

  def default_branch_for(project)
    project.branches.find_by(name: "main") || project.branches.first
  end

  def authorize_user!
    membership = @project.project_memberships.find_by(user_id: current_user.id)
    unless @project.owner == current_user || (membership&.active?)
      redirect_to projects_path, alert: "You are not authorized to access this project."
    end
  end

  def git_author_hash
    {
      name: current_user.username || current_user.email,
      email: current_user.email,
      time: Time.now
    }
  end
end
