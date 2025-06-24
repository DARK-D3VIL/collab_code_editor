# app/mailers/github_notification_mailer.rb
class GithubNotificationMailer < ApplicationMailer
  def push_success(user, project)
    @user = user
    @project = project
    @project_url = project_url(@project)

    mail(
      to: @user.email,
      subject: "✅ Code successfully pushed to GitHub - #{@project.name}"
    )
  end

  def push_failure(user, project, error_message)
    @user = user
    @project = project
    @error_message = error_message
    @project_url = project_url(@project)

    mail(
      to: @user.email,
      subject: "❌ GitHub push failed - #{@project.name}"
    )
  end

  def clone_success(user, project)
    @user = user
    @project = project
    @project_url = project_url(@project)

    mail(
      to: @user.email,
      subject: "✅ Repository cloned successfully - #{@project.name}"
    )
  end

  def clone_failure(user, error_message)
    @user = user
    @error_message = error_message

    mail(
      to: @user.email,
      subject: "❌ Repository clone failed"
    )
  end

  private

  def project_url(project)
    Rails.application.routes.url_helpers.project_project_files_url(
      project,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )
  end
end
