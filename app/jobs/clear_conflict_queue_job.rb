class ClearConflictQueueJob < ApplicationJob
  queue_as :default

  def perform(project_id:, user_id:, branch:, path:, **kwargs)
    cleared_count = ConflictQueue.where(
      project_id: project_id,
      user_id: user_id,
      branch: branch,
      file_path: path
    ).delete_all

    Rails.logger.info("Deleted #{cleared_count} conflict queue entries for user #{user_id} in project #{project_id} on branch #{branch}")
  end
end
