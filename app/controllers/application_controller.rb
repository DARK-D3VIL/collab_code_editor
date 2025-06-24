class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  rescue_from ActiveRecord::RecordNotFound, with: :render_404
  rescue_from ActionController::RoutingError, with: :render_404
  rescue_from ActionController::UnknownFormat, with: :render_422
  rescue_from ActionController::ParameterMissing, with: :render_422
  rescue_from StandardError, with: :render_500 unless Rails.env.development?

  def render_404(exception = nil)
    logger.info "Rendering 404: #{exception.message}" if exception
    render template: "errors/not_found", status: :not_found
  end

  def render_422(exception = nil)
    logger.info "Rendering 422: #{exception.message}" if exception
    render template: "errors/unprocessable_entity", status: :unprocessable_entity
  end

  def render_500(exception = nil)
    logger.error "Rendering 500: #{exception.message}" if exception
    render template: "errors/internal_server_error", status: :internal_server_error
  end

  protected

  def current_user_membership
    return nil unless @project && current_user
    @current_user_membership ||= @project.project_memberships.find_by(user_id: current_user.id)
  end

  helper_method :current_user_membership
end
