# app/controllers/project_settings_controller.rb
class ProjectSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :authorize_owner!

  # GET /projects/:project_id/settings
  def show
    @project_members = @project.project_memberships
                               .includes(:user)
                               .where(active: true)
                               .where.not(user: current_user)
    
    # Get potential users to transfer ownership to (active members only)
    @potential_owners = @project_members.joins(:user).where(role: 'writer').map(&:user)
  end

  # PATCH /projects/:project_id/settings
  def update
    case params[:setting_type]
    when 'basic'
      update_basic_settings
    when 'transfer_ownership'
      transfer_ownership
    when 'ai_training'
      start_ai_training
    else
      redirect_to project_settings_path(@project), alert: 'Invalid setting type.'
    end
  end

  # DELETE /projects/:project_id/settings (delete project)
  def destroy
    project_name = @project.name
    
    # Delete project repository files
    repo_path = Rails.root.join("storage", "projects", "project_#{@project.id}")
    FileUtils.rm_rf(repo_path) if Dir.exist?(repo_path)
    
    # Delete project record (dependent associations will be destroyed automatically)
    @project.destroy!
    
    Rails.logger.info "User #{current_user.email} deleted project #{project_name} (ID: #{@project.id})"
    
    redirect_to projects_path, notice: "Project '#{project_name}' has been permanently deleted."
  rescue => e
    Rails.logger.error "Failed to delete project #{@project.id}: #{e.message}"
    redirect_to project_settings_path(@project), alert: 'Failed to delete project. Please try again.'
  end

  # GET /projects/:project_id/settings/ai_training_status
  def ai_training_status
    render json: {
      status: @project.ai_training_status,
      model_available: @project.ai_model_available?,
      can_start_training: @project.can_start_ai_training?,
      latest_job: @project.latest_training_job&.as_json(only: [:status, :progress, :error_message, :created_at])
    }
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: 'Project not found or you do not have access.'
  end

  def authorize_owner!
    unless @project.owner == current_user
      redirect_to project_path(@project), alert: 'Only the project owner can access settings.'
    end
  end

  def project_params
    params.require(:project).permit(:name)
  end

  def update_basic_settings
    old_name = @project.name
    generate_new_slug = params[:generate_new_slug] == 'true'
    
    if @project.update(project_params)
      # Generate new slug if checkbox is checked
      if generate_new_slug
        new_slug = SecureRandom.hex(3)
        @project.update!(slug: new_slug)
        flash[:notice] = "Project updated successfully! New project code: #{new_slug}"
      else
        flash[:notice] = 'Project updated successfully!'
      end
    else
      flash[:alert] = "Failed to update project: #{@project.errors.full_messages.join(', ')}"
    end
    
    redirect_to project_settings_path(@project)
  end

  def transfer_ownership
    new_owner_id = params[:new_owner_id]
    new_owner = User.find_by(id: new_owner_id)
    
    unless new_owner
      redirect_to project_settings_path(@project), alert: 'Invalid user selected.'
      return
    end
    
    # Verify new owner is an active member
    unless @project.project_memberships.exists?(user: new_owner, active: true)
      redirect_to project_settings_path(@project), alert: 'Selected user is not an active member of this project.'
      return
    end
    
    # Verify current password for security
    unless current_user.valid_password?(params[:current_password])
      redirect_to project_settings_path(@project), alert: 'Invalid password. Ownership transfer cancelled.'
      return
    end
    
    old_owner = @project.owner
    
    ActiveRecord::Base.transaction do
      # Update project ownership
      @project.update!(owner: new_owner)
      
      # Update the new owner's membership to ensure they have full access
      new_owner_membership = @project.project_memberships.find_by(user: new_owner)
      new_owner_membership&.update!(role: 'writer')
      
      # Create a regular membership for the old owner
      old_owner_membership = @project.project_memberships.find_by(user: old_owner)
      if old_owner_membership
        old_owner_membership.update!(role: 'writer')
      else
        @project.project_memberships.create!(user: old_owner, role: 'writer', active: true)
      end
    end
    
    Rails.logger.info "Project ownership transferred: #{@project.name} (#{@project.slug}) from #{old_owner.email} to #{new_owner.email}"
    
    redirect_to projects_path, notice: "Ownership of '#{@project.name}' has been transferred to #{new_owner.username || new_owner.email}. You are now a regular member."
    
  rescue => e
    Rails.logger.error "Ownership transfer failed: #{e.message}"
    redirect_to project_settings_path(@project), alert: 'Failed to transfer ownership. Please try again.'
  end

  def start_ai_training
    force_retrain = params[:force_retrain] == 'true'
    
    # Allow starting new training even if completed
    if @project.ai_training_status == 'completed' && force_retrain
      Rails.logger.info "🔄 Force retraining requested for completed project #{@project.id}"
      
      # Reset project status to allow new training
      @project.update!(
        ai_training_status: 'not_started',
        ai_model_trained_at: nil
      )
    elsif !@project.can_start_ai_training? && !force_retrain
      redirect_to project_settings_path(@project), alert: 'AI training is already in progress or not available.'
      return
    end
    
    training_job = @project.start_ai_training!(current_user, force_retrain: force_retrain)
    
    if training_job
      flash[:notice] = if force_retrain
                        'New AI model training started! This will replace the existing model and take about 15-20 minutes. You can check the progress below.'
                      else
                        'AI model training started! This will take about 15-20 minutes. You can check the progress below.'
                      end
    else
      flash[:alert] = 'Failed to start AI training. Please check if the AI service is available and try again.'
    end
    
    redirect_to project_settings_path(@project)
  end
end