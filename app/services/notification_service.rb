# app/services/notification_service.rb
class NotificationService
  def self.notify_user(user, notification_type, context = nil)
    new(user, notification_type, context).send_notification
  end

  def initialize(user, notification_type, context = nil)
    @user = user
    @notification_type = notification_type
    @context = context
  end

  def send_notification
    case @notification_type
    when :push_success
      send_push_success_notification
    when :push_failure
      send_push_failure_notification
    when :clone_success
      send_clone_success_notification
    when :clone_failure
      send_clone_failure_notification
    else
      Rails.logger.warn "Unknown notification type: #{@notification_type}"
    end
  end

  private

  def send_push_success_notification
    # Send email notification
    GithubNotificationMailer.push_success(@user, @context).deliver_now

    Rails.logger.info "Push success notification sent to user #{@user.id} for project #{@context.id}"
  end

  def send_push_failure_notification
    # Send email notification
    GithubNotificationMailer.push_failure(@user, @context, @context).deliver_now

    Rails.logger.error "Push failure notification sent to user #{@user.id}, error: #{@context}"
  end

  def send_clone_success_notification
    GithubNotificationMailer.clone_success(@user, @context).deliver_now

    Rails.logger.info "Clone success notification sent to user #{@user.id} for project #{@context.id}"
  end

  def send_clone_failure_notification
    GithubNotificationMailer.clone_failure(@user, @context).deliver_now

    Rails.logger.error "Clone failure notification sent to user #{@user.id}, error: #{@context}"
  end
end
