# app/jobs/email_verification_cleanup_job.rb
class EmailVerificationCleanupJob < ApplicationJob
  queue_as :default

  def perform
    expired_count = EmailVerification.expired.count
    EmailVerification.cleanup_expired

    Rails.logger.info "Cleaned up #{expired_count} expired email verifications"

    # Optional: Clean up unverified users older than 24 hours
    unverified_users = User.where(email_verified_at: nil, provider: nil)
                          .where("created_at < ?", 24.hours.ago)

    if unverified_users.any?
      deleted_count = unverified_users.count
      unverified_users.destroy_all
      Rails.logger.info "Deleted #{deleted_count} unverified users older than 24 hours"
    end
  end
end

# lib/tasks/email_verification.rake
namespace :email_verification do
  desc "Clean up expired email verifications"
  task cleanup: :environment do
    EmailVerificationCleanupJob.perform_now
  end
end
