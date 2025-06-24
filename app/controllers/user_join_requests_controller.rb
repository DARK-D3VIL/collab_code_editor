# app/controllers/user_join_requests_controller.rb
class UserJoinRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_join_request, only: [:destroy]

  def index
    @pending_requests = current_user.project_join_requests
                                   .pending
                                   .includes(:project)
                                   .order(created_at: :desc)
  end

  def destroy
    if @join_request.destroy
      redirect_to user_join_requests_path, notice: "Join request cancelled successfully."
    else
      redirect_to user_join_requests_path, alert: "Failed to cancel join request."
    end
  end

  private

  def set_join_request
    @join_request = current_user.project_join_requests.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to user_join_requests_path, alert: "Join request not found."
  end
end
