class ProjectMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :authorize_owner!

  def index
    @active_memberships = @project.project_memberships
                                  .includes(:user)
                                  .where(active: true)
                                  .where.not(user_id: @project.owner_id)

    @inactive_memberships = @project.project_memberships
                                    .includes(:user)
                                    .where(active: false)
                                    .where.not(user_id: @project.owner_id)
  end

  def deactivate
    membership = @project.project_memberships.find_by(user_id: params[:id])
    if membership
      membership.update(active: false)
      redirect_to project_project_members_path(@project), notice: "Member removed successfully."
    else
      redirect_to project_project_members_path(@project), alert: "Member not found."
    end
  end

  def activate
    membership = @project.project_memberships.find_by(user_id: params[:id])
    if membership
      membership.update(active: true)
      redirect_to project_project_members_path(@project), notice: "Member re-added successfully."
    else
      redirect_to project_project_members_path(@project), alert: "Member not found."
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_owner!
    unless @project.owner_id == current_user.id
      redirect_to project_projects_path, alert: "Only the project owner can manage members."
    end
  end
end
