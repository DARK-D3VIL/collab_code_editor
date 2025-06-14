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

    # Add pending join requests
    @pending_requests = @project.project_join_requests.pending.includes(:user)
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

  # NEW: Approve join request
  def approve_request
    join_request = @project.project_join_requests.pending.find(params[:request_id])
    if join_request
      begin
        # Find the main branch (like in the original join action)
        main_branch = @project.branches.find_by(name: "main")

        # Create the project membership with the default branch
        ProjectMembership.create!(
          user: join_request.user,
          project: @project,
          current_branch: main_branch
        )

        # Now approve the request
        join_request.approve!

        # Send approval notification email
        ProjectRequestMailerJob.perform_later(:approved, join_request.user.id, @project.id)
        redirect_to project_project_members_path(@project), notice: "Join request approved successfully."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to project_project_members_path(@project), alert: "Failed to approve request: #{e.message}"
      end
    else
      redirect_to project_project_members_path(@project), alert: "Join request not found."
    end
  end

  # NEW: Reject join request
  def reject_request
    join_request = @project.project_join_requests.pending.find(params[:request_id])

    if join_request
      user = join_request.user
      join_request.reject!
      # Send rejection notification email
      ProjectRequestMailerJob.perform_later(:rejected, user.id, @project.id)
      redirect_to project_project_members_path(@project), notice: "Join request rejected."
    else
      redirect_to project_project_members_path(@project), alert: "Join request not found."
    end
  end

  # NEW: Change member role
  def change_role
    membership = @project.project_memberships.find_by(user_id: params[:id])
    new_role = params[:role]

    if membership && [ "reader", "writer" ].include?(new_role)
      membership.update(role: new_role)
      redirect_to project_project_members_path(@project),
                  notice: "Member role updated to #{new_role.humanize} successfully."
    else
      redirect_to project_project_members_path(@project), alert: "Failed to update member role."
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_owner!
    unless @project.owner_id == current_user.id
      redirect_to projects_path, alert: "Only the project owner can manage members."
    end
  end
end
