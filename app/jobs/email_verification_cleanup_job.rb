# app/jobs/email_verification_cleanup_job.rb
class EmailVerificationCleanupJob < ApplicationJob
  queue_as :default
  attr_accessor :jid, :_context  # For Sidekiq, this will be set automatically

  def perform
    expired_count = EmailVerification.expired.count
    EmailVerification.cleanup_expired

    Rails.logger.info "Cleaned up #{expired_count} expired email verifications"

    unverified_users = User.where(email_verified_at: nil, provider: nil)
                          .where("created_at < ?", 24.hours.ago)

    if unverified_users.any?
      deleted_count = unverified_users.count
      unverified_users.destroy_all
      Rails.logger.info "Deleted #{deleted_count} unverified users older than 24 hours"
    end
  end
end
