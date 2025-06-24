class ProjectGitController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :authorize_user!
  before_action :set_repo
  before_action :set_git_service
  before_action :check_write_permission, only: [ :create_branch, :switch, :revert, :rollback, :merge, :destroy_branch ]

  # Cache frequently accessed data
  before_action :set_current_membership, only: [ :index, :branches, :create_branch, :switch ]
  before_action :set_current_branch, only: [ :index, :branches, :switch, :merge ]

  def index
    # Use includes to avoid N+1 queries
    @branches = Rails.cache.fetch("project_#{@project.id}_branches_with_commits", expires_in: 10.minutes) do
      @project.branches.includes(:commits).order(:created_at).to_a
    end
    @selected_branch = @current_branch

    # Limit commits to recent ones for better performance
    @commits = Rails.cache.fetch("project_#{@project.id}_branch_#{@selected_branch.id}_commits", expires_in: 5.minutes) do
      all_commits = @git_service.commits_for_branch(@selected_branch.name)
      all_commits.first(50) # Limit to 50 most recent commits
    end
  end

  def branches
    # Cache branches list
    @branches = Rails.cache.fetch("project_#{@project.id}_branches_list", expires_in: 10.minutes) do
      @project.branches.order(:created_at).to_a
    end
    @current_branch = @current_branch.name
  end

  def create_branch
    name = params[:name]
    base_sha = Rails.cache.fetch("project_#{@project.id}_branch_#{@current_branch.id}_current_sha", expires_in: 2.minutes) do
      @git_service.current_commit_sha(@current_branch.name)
    end

    result = @git_service.create_branch(name, base_sha, current_user.id)

    if result.success?
      # Invalidate relevant caches
      invalidate_project_caches
      redirect_to project_git_branches_path(@project), notice: result.message
    else
      redirect_to project_git_branches_path(@project), alert: result.message
    end
  end

  def switch
    branch = @project.branches.find(params[:id])

    # Use update_column for better performance on single column update
    @current_membership.update_column(:current_branch_id, branch.id)

    # Invalidate user's branch cache
    Rails.cache.delete("user_#{current_user.id}_project_#{@project.id}_current_branch")

    redirect_to project_project_files_path(@project), notice: "Switched to branch #{branch.name}"
  end

  def commits
    @branch = @project.branches.find_by(id: params[:id]) || @project.branches.find_by!(name: params[:id])

    # Cache commits with pagination
    page = (params[:page] || 1).to_i
    per_page = 50
    cache_key = "project_#{@project.id}_branch_#{@branch.id}_commits_page_#{page}"

    @commits = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      all_commits = @git_service.commits_for_branch(@branch.name)
      # Manual pagination since GitService doesn't support it
      start_index = (page - 1) * per_page
      all_commits[start_index, per_page] || []
    end
  end

  def commit_diff
    # Cache diff data as it's expensive to compute
    cache_key = "project_#{@project.id}_commit_#{params[:sha]}_diff"
    @diff = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      @git_service.commit_diff(params[:sha])
    end
  end

  def revert
    sha = params[:sha]
    author = git_author_hash

    result = @git_service.revert_commit(sha, author, current_user)

    if result[:success]
      invalidate_project_caches
      redirect_to project_git_branch_commits_path(@project, params[:id]), notice: "Reverted commit #{sha[0..6]}"
    elsif result[:conflict]
      redirect_to project_git_branch_commits_path(@project, params[:id]), alert: "Conflict occurred during revert. Resolve manually."
    else
      redirect_to project_git_branch_commits_path(@project, params[:id]), alert: "Revert failed."
    end
  end

  def rollback
    sha = params[:sha]
    result = @git_service.rollback_to_commit(sha)

    if result[:success]
      invalidate_project_caches
      redirect_to project_git_branch_commits_path(@project, params[:id]), notice: "Rolled back commit #{sha[0..6]}"
    elsif result[:conflict]
      redirect_to project_git_branch_commits_path(@project, params[:id]), alert: "Conflict occurred during rollback. Resolve manually."
    else
      redirect_to project_git_branch_commits_path(@project, params[:id]), alert: "Rollback failed."
    end
  end

  def merge
    source_branch = @project.branches.find(params[:id])
    target_branch_name = @current_branch.name

    result = @git_service.merge_branch(source_branch.name, target_branch_name, author: git_author_hash)

    if result[:success]
      invalidate_project_caches
      redirect_to project_git_branches_path(@project), notice: "Merged successfully into #{target_branch_name}. Commit: #{result[:sha]}"
    elsif result[:conflict]
      redirect_to project_git_branches_path(@project), alert: "Merge conflict occurred. Please resolve manually."
    else
      redirect_to project_git_branches_path(@project), alert: "Merge failed."
    end
  end

  def destroy_branch
    branch = @project.branches.find(params[:id])

    if branch.name == "main" || branch.id == @current_branch.id
      redirect_to project_git_branches_path(@project), alert: "Cannot delete main or current branch."
      return
    end

    branch.destroy
    invalidate_project_caches
    redirect_to project_git_branches_path(@project), notice: "Branch deleted successfully."
  end

  def show
    # Use cached branch names
    @branches = Rails.cache.fetch("project_#{@project.id}_branch_names", expires_in: 10.minutes) do
      @project.branches.pluck(:name)
    end

    return if @branches.blank? || !@repo

    # Cache the expensive git graph computation
    cache_key = "project_#{@project.id}_git_graph_v3"
    @graph_commits = Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
      build_git_graph(@branches)
    end
  end

  private

  def set_project
    # Load full project to avoid missing attribute errors
    @project = Rails.cache.fetch("project_#{params[:project_id]}_full", expires_in: 10.minutes) do
      Project.find(params[:project_id])
    end
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

  def set_current_membership
    @current_membership = Rails.cache.fetch("user_#{current_user.id}_project_#{@project.id}_membership", expires_in: 5.minutes) do
      current_user.project_memberships.find_by(project_id: @project.id)
    end
  end

  def set_current_branch
    @current_branch = Rails.cache.fetch("user_#{current_user.id}_project_#{@project.id}_current_branch", expires_in: 5.minutes) do
      current_branch_for_project
    end
  end

  def current_membership
    @current_membership ||= set_current_membership
  end

  def current_branch_for_project
    # Get the current branch for the user
    if @current_membership&.current_branch_id
      branch = @project.branches.find_by(id: @current_membership.current_branch_id)
      return branch if branch
    end

    # Fallback to default branch
    default_branch_for(@project)
  end

  def default_branch_for(project)
    Rails.cache.fetch("project_#{project.id}_default_branch", expires_in: 1.hour) do
      project.branches.find_by(name: "main") || project.branches.first
    end
  end

  def authorize_user!
    # Use cached membership data
    membership = @current_membership || set_current_membership
    unless @project.owner_id == current_user.id || (membership&.active?)
      redirect_to projects_path, alert: "You are not authorized to access this project."
    end
  end

  def check_write_permission
    return if @project.owner_id == current_user.id

    membership = @current_membership || set_current_membership
    unless membership&.can_write?
      redirect_to project_git_branches_path(@project), alert: "You don't have permission to perform this action. Read-only access."
      false
    end
  end

  def git_author_hash
    @git_author_hash ||= {
      name: current_user.username || current_user.email,
      email: current_user.email,
      time: Time.now
    }
  end

  def time_ago(time)
    # Cache time calculations for frequently accessed commits
    Rails.cache.fetch("time_ago_#{time.to_i}", expires_in: 1.minute) do
      calculate_time_ago(time)
    end
  end

  def calculate_time_ago(time)
    diff = Time.current - time

    case diff
    when 0..59
      "just now"
    when 60..3599
      minutes = (diff / 60).round
      "#{minutes} #{'minute'.pluralize(minutes)} ago"
    when 3600..86399
      hours = (diff / 3600).round
      "#{hours} #{'hour'.pluralize(hours)} ago"
    when 86400..2591999
      days = (diff / 86400).round
      "#{days} #{'day'.pluralize(days)} ago"
    when 2592000..31535999
      months = (diff / 2592000).round
      "#{months} #{'month'.pluralize(months)} ago"
    else
      years = (diff / 31536000).round
      "#{years} #{'year'.pluralize(years)} ago"
    end
  end

  def can_write?
    @can_write ||= @project.owner_id == current_user.id || (@current_membership || set_current_membership)&.can_write?
  end
  helper_method :can_write?

  # Optimized git graph building with limits and batching
  def build_git_graph(branches)
    graph_commits = []
    repo = @repo
    commit_limit = 500 # Limit total commits for performance
    processed_commits = Set.new

    return [] if branches.blank? || !repo

    walker = Rugged::Walker.new(repo)

    branches.each do |branch_name|
      next unless repo.branches.exist?(branch_name)
      break if graph_commits.size >= commit_limit

      begin
        walker.reset
        walker.push(repo.branches[branch_name].target_id)
        walker.sorting(Rugged::SORT_DATE | Rugged::SORT_REVERSE)

        # Limit commits per branch
        branch_commit_count = 0
        max_per_branch = [ 100, commit_limit - graph_commits.size ].min

        walker.each do |commit|
          break if branch_commit_count >= max_per_branch || graph_commits.size >= commit_limit
          next if processed_commits.include?(commit.oid)

          processed_commits.add(commit.oid)
          branch_commit_count += 1

          commit_message = commit.message.lines.first&.chomp || "No commit message"

          graph_commits << {
            sha: commit.oid,
            message: commit_message.length > 60 ? "#{commit_message[0..57]}..." : commit_message,
            author: commit.author[:name],
            time: commit.time.iso8601,
            branch: branch_name,
            parents: commit.parent_ids,
            author_email: commit.author[:email],
            commit_time: commit.time.strftime("%Y-%m-%d %H:%M:%S"),
            relative_time: calculate_time_ago(commit.time)
          }
        end
      rescue Rugged::InvalidError, Rugged::ReferenceError => e
        Rails.logger.warn "Git graph error for branch #{branch_name}: #{e.message}"
        next
      end
    end

    # Sort by time (newest first)
    graph_commits.sort_by { |c| Time.parse(c[:time]) }.reverse
  rescue => e
    Rails.logger.error "Git graph building failed: #{e.message}"
    []
  end

  # Cache invalidation helper
  def invalidate_project_caches
    # Clear project-specific caches
    Rails.cache.delete_matched("project_#{@project.id}_*")
    Rails.cache.delete_matched("user_#{current_user.id}_project_#{@project.id}_*")

    # Clear specific branch caches for all users
    @project.project_memberships.pluck(:user_id).each do |user_id|
      Rails.cache.delete("user_#{user_id}_project_#{@project.id}_current_branch")
      Rails.cache.delete("user_#{user_id}_project_#{@project.id}_membership")
    end
  end
end
