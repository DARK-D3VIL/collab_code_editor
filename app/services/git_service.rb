require "ostruct"


class GitService
  def initialize(project)
    @project = project
    @repo_path = Rails.root.join("storage", "projects", "project_#{project.id}")
    @repo = Rugged::Repository.new(@repo_path.to_s)
  end

  def list_branches
    @repo.branches.each_name(:local).to_a
  end

  def current_commit_sha(branch_name)
    @repo.branches[branch_name]&.target_id
  end

  def create_branch(name, base_commit_sha, user_id)
    return OpenStruct.new(success?: false, message: "Branch already exists") if @repo.branches[name]

    # Create Git branch
    @repo.create_branch(name, base_commit_sha)

    # Create DB record
    branch = Branch.create!(
      project_id: @project.id,
      name: name,
      created_by: user_id
    )

    OpenStruct.new(success?: true, message: "Branch '#{name}' created successfully", branch: branch)
  rescue => e
    OpenStruct.new(success?: false, message: "Error creating branch: #{e.message}")
  end


  def commits_for_branch(branch_name)
    branch = @repo.branches[branch_name]
    return [] unless branch

    walker = Rugged::Walker.new(@repo)
    walker.sorting(Rugged::SORT_DATE)
    walker.push(branch.target_id)

    walker.map do |commit|
      {
        sha: commit.oid,
        message: commit.message,
        author: commit.author[:name],
        time: commit.time,
        parents: commit.parent_ids
      }
    end
  end

  def commit_diff(sha)
    commit = @repo.lookup(sha)
    parent = commit.parents.first

    diff = if parent
            parent.diff(commit)
    else
      commit.diff(nil)  # first commit
    end

    diff&.patch || ""
  rescue => e
    Rails.logger.error("Commit diff failed: #{e.message}")
    nil
  end


  # def rollback_file_to_commit(file, commit_sha)
  #   commit = @repo.lookup(commit_sha)
  #   entry = commit.tree.path(File.join(file.path, file.name)) rescue nil
  #   return false unless entry

  #   blob = @repo.read(entry[:oid])
  #   file_path = File.join(@repo.workdir, file.path, file.name)
  #   File.write(file_path, blob.data)
  #   true
  # end

  def rollback_to_commit(sha)
    commit = @repo.lookup(sha)
    return { success: false, error: "Commit not found" } unless commit

    @repo.reset(commit.oid, :hard)

    cleanup_rolled_back_commits(sha)

    { success: true }
  rescue => e
    { success: false, error: e.message }
  end



  # def revert_commit(sha, author, user)
  #   commit_to_revert = @repo.lookup(sha)
  #   current_commit = @repo.head.target

  #   revert_index = @repo.revert_commit(commit_to_revert, current_commit)

  #   if revert_index.conflicts?
  #     return { success: false, conflict: true }
  #   end

  #   tree_oid = revert_index.write_tree(@repo)

  #   branch_name = @repo.head.name.sub("refs/heads/", "")
  #   branch = @project.branches.find_by(name: branch_name)

  #   commit_message = "Revert commit #{sha[0..6]}"
  #   commit_oid = Rugged::Commit.create(@repo, {
  #     message: commit_message,
  #     author: author,
  #     committer: author,
  #     tree: tree_oid,
  #     parents: [current_commit],
  #     update_ref: "HEAD"
  #   })

  #   # Save to DB
  #   Commit.create!(
  #     user_id: user.id,
  #     project_id: @project.id,
  #     branch_id: branch.id,
  #     message: commit_message,
  #     sha: commit_oid,
  #     parent_sha: current_commit.oid
  #   )

  #   { success: true, sha: commit_oid }
  # end


  def switch_branch(branch_name)
    `cd #{@repo_path} && git checkout #{branch_name}`
  end

  def merge_branch(source_branch_name, target_branch_name = "main", author:)
    @repo.checkout(target_branch_name)

    source = @repo.branches[source_branch_name]
    target = @repo.branches[target_branch_name]

    merge_index = @repo.merge_commits(target.target, source.target)

    if merge_index.conflicts?
      return { success: false, conflict: true }
    else
      tree_oid = merge_index.write_tree(@repo)

      commit_oid = Rugged::Commit.create(@repo, {
        message: "Merged #{source_branch_name} into #{target_branch_name}",
        author: author,
        committer: author,
        tree: tree_oid,
        parents: [target.target, source.target],
        update_ref: "HEAD"
      })

      { success: true, sha: commit_oid }
    end
  end

  def repo
    @repo
  end

  def cleanup_rolled_back_commits(rollback_to_sha)
    branch_name = @repo.head.name.sub("refs/heads/", "")
    branch = @project.branches.find_by(name: branch_name)
    return unless branch

    # Step 1: Get SHAs reachable from the rollback target
    reachable_shas = Set.new
    walker = Rugged::Walker.new(@repo)
    walker.sorting(Rugged::SORT_DATE)
    walker.push(rollback_to_sha)
    walker.each { |c| reachable_shas << c.oid }
    walker.reset

    # Step 2: Find commits in this branch that are no longer reachable
    unreachable_commits = Commit.where(project_id: @project.id, branch_id: branch.id)
                                .where.not(sha: reachable_shas.to_a)

    # Step 3: Filter out any commits that are still reachable from another branch
    commits_to_delete = unreachable_commits.reject do |commit|
      # Check if any other branch still reaches this commit
      @project.branches.where.not(id: branch.id).any? do |other_branch|
        rugged_branch = @repo.branches[other_branch.name]
        next false unless rugged_branch

        other_walker = Rugged::Walker.new(@repo)
        other_walker.sorting(Rugged::SORT_DATE)
        other_walker.push(rugged_branch.target_id)

        found = other_walker.any? { |c| c.oid == commit.sha }
        other_walker.reset
        found
      end
    end

    # Step 4: Delete commits that are safe to remove
    Commit.where(id: commits_to_delete.map(&:id)).delete_all
  end
end
