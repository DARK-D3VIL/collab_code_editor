# app/controllers/errors_controller.rb
class ErrorsController < ApplicationController
  layout "application" # Use your app's layout

  def not_found
    render status: :not_found
  end

  def internal_server_error
    render status: :internal_server_error
  end

  def unprocessable_entity
    render status: :unprocessable_entity
  end
end
