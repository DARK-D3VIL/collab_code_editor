# app/jobs/email_verification_job.rb
class EmailVerificationJob < ApplicationJob
  queue_as :mailers

  # Retry failed jobs with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(verification_id)
    verification = EmailVerification.find_by(id: verification_id)

    # Don't send if verification doesn't exist or is expired
    return unless verification&.active?

    # Don't send if user is already verified
    return if verification.user.email_verified?

    # Send the email
    UserMailer.email_verification(verification).deliver_now

    Rails.logger.info "Email verification sent to #{verification.email} for user #{verification.user.username}"

  rescue => e
    Rails.logger.error "Failed to send email verification: #{e.message}"
    raise e # Re-raise to trigger retry logic
  end
end
