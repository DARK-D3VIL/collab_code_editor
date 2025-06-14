class ProjectRequestMailerJob < ApplicationJob
  queue_as :default

  def perform(mail_type, user_id, project_id, join_request_id = nil)
    user = User.find_by(id: user_id)
    project = Project.find_by(id: project_id)
    join_request = join_request_id && ProjectJoinRequest.find_by(id: join_request_id)

    return unless user && project

    case mail_type.to_sym
    when :rejected
      ProjectRequestMailer.request_rejected(user, project).deliver_now
    when :approved
      ProjectRequestMailer.request_approved(user, project).deliver_now
    when :new_join_request
      ProjectRequestMailer.new_join_request(user, join_request).deliver_now if join_request
    end
  end
end
