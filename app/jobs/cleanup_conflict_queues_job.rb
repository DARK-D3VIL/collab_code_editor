class CleanupConflictQueuesJob < ApplicationJob
  queue_as :default

  def perform
    threshold_time = 15.minutes.ago
    old_conflicts = ConflictQueue.where("created_at < ?", threshold_time)

    count = old_conflicts.count
    old_conflicts.delete_all

    Rails.logger.info "[CleanupConflictQueuesJob] Deleted #{count} old conflict queue records older than 15 minutes."
  end
end
