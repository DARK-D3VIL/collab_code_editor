# app/jobs/push_to_github_job.rb
class PushToGithubJob < ApplicationJob
  queue_as :default

  def perform(project_id:, branch_id:, user_id:)
    project = Project.find(project_id)
    branch = Branch.find(branch_id)
    user = User.find(user_id)

    service = GithubPushService.new(project, branch, user)
    result = service.call

    if result.success?
      NotificationService.notify_user(user, :push_success, project)
      Rails.logger.info "Successfully pushed project #{project.id} to GitHub for user #{user.id}"
    else
      NotificationService.notify_user(user, :push_failure, result.error)
      Rails.logger.error "Failed to push project #{project.id} to GitHub for user #{user.id}: #{result.error}"
    end
  rescue => e
    Rails.logger.error "PushToGithubJob failed: #{e.message}"
    # Try to notify user even if job fails
    begin
      user = User.find(user_id)
      NotificationService.notify_user(user, :push_failure, e.message)
    rescue => notification_error
      Rails.logger.error "Failed to send failure notification: #{notification_error.message}"
    end
    raise e # Re-raise to trigger Sidekiq retry
  end
end
