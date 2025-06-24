# app/jobs/cleanup_expired_conflicts_job.rb
class CleanupExpiredConflictsJob < ApplicationJob
  queue_as :default

  def perform
    # Clean up expired conflicts (older than 10 minutes)
    ConflictQueue.where("created_at < ?", 10.minutes.ago).destroy_all

    Rails.logger.info "Cleaned up expired conflicts"
  end
end
