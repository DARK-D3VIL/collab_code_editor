# app/mailers/project_request_mailer.rb
class ProjectRequestMailer < ApplicationMailer

  def new_join_request(owner, join_request)
    @owner = owner
    @requester = join_request.user
    @project = join_request.project
    @join_request = join_request

    mail(
      to: @owner.email,
      subject: "New join request for #{@project.name}"
    )
  end

  def request_approved(user, project)
    @user = user
    @project = project

    mail(
      to: @user.email,
      subject: "Your request to join #{@project.name} has been approved!"
    )
  end

  def request_rejected(user, project)
    @user = user
    @project = project

    mail(
      to: @user.email,
      subject: "Your request to join #{@project.name} has been declined"
    )
  end
end
