# lib/tasks/email_verification.rake
namespace :email_verification do
  desc "Clean up expired email verifications"
  task cleanup: :environment do
    EmailVerificationCleanupJob.perform_now
    puts "Email verification cleanup job enqueued"
  end
end
