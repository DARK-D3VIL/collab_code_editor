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
    else
      NotificationService.notify_user(user, :push_failure, result.error)
    end
  end
end
