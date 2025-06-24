# app/controllers/user_settings_controller.rb
class UserSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [:index, :update_profile, :update_password, :export_data, :request_deletion_otp, :destroy_account]
  before_action :require_current_password, only: [:update_password]

  # GET /settings
  def index
    # Load user's owned projects
    @owned_projects = @user.owned_projects.includes(:users)
    
    # Get joined projects by going through project_memberships directly
    # This ensures we only get projects where the user is a member (not owner)
    @joined_projects = Project.joins(:project_memberships)
                              .where(project_memberships: { user: @user, active: true })
                              .where.not(owner: @user)  # Explicitly exclude owned projects
                              .includes(:owner)
                              .distinct
    
    @pending_requests = @user.project_join_requests.includes(:project)
  end

  # PATCH /settings/profile
  def update_profile
    if @user.update(profile_params)
      redirect_to user_settings_path, notice: 'Profile updated successfully.'
    else
      load_user_projects  # Use helper method to reload projects
      
      flash.now[:alert] = 'Failed to update profile. Please check the errors below.'
      render :index, status: :unprocessable_entity
    end
  end

  # PATCH /settings/password
  def update_password
    if @user.update_with_password(password_params)
      # Sign in the user again to maintain session after password change
      bypass_sign_in(@user)
      redirect_to user_settings_path, notice: 'Password updated successfully.'
    else
      load_user_projects  # Use helper method to reload projects
      
      flash.now[:alert] = 'Please enter the correct current password.'
      render :index, status: :unprocessable_entity
    end
  end

  # DELETE /projects/:id/leave
  def leave_project
    @project = Project.find(params[:id])
    
    # Check if user is a member (not owner) with active membership
    membership = @project.project_memberships.find_by(user: current_user, active: true)
    
    unless membership
      redirect_to user_settings_path, alert: 'You are not a member of this project.'
      return
    end

    if @project.owner == current_user
      redirect_to user_settings_path, alert: 'You cannot leave a project you own. Transfer ownership or delete the project instead.'
      return
    end

    # Completely remove the membership instead of just deactivating
    membership.destroy!
    
    # Log the activity
    Rails.logger.info "User #{current_user.email} left project #{@project.name} (#{@project.slug})"
    
    redirect_to user_settings_path, notice: "You have successfully left the project '#{@project.name}'."
  rescue ActiveRecord::RecordNotFound
    redirect_to user_settings_path, alert: 'Project not found.'
  end

  # DELETE /projects/:id/delete
  def delete_project
    @project = Project.find(params[:id])
    
    unless @project.owner == current_user
      redirect_to user_settings_path, alert: 'You can only delete projects you own.'
      return
    end

    project_name = @project.name
    
    # Delete the project (associations will be handled by dependent: :destroy)
    @project.destroy!
    
    # Log the activity
    Rails.logger.info "User #{current_user.email} deleted project #{project_name}"
    
    redirect_to user_settings_path, notice: "Project '#{project_name}' has been permanently deleted."
  rescue ActiveRecord::RecordNotFound
    redirect_to user_settings_path, alert: 'Project not found.'
  rescue => e
    Rails.logger.error "Failed to delete project: #{e.message}"
    redirect_to user_settings_path, alert: 'Failed to delete project. Please try again.'
  end

  # GET /settings/export
  def export_data
    begin
      # Generate user data export
      user_data = generate_user_data_export
      
      # Create filename with timestamp
      filename = "#{@user.username || @user.email.split('@').first}_data_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      
      # Log the export
      Rails.logger.info "User #{@user.email} exported their data"
      
      send_data user_data.to_json, 
                filename: filename,
                type: 'application/json',
                disposition: 'attachment'
    rescue => e
      Rails.logger.error "Failed to export user data: #{e.message}"
      redirect_to user_settings_path, alert: 'Failed to export data. Please try again.'
    end
  end

  # POST /settings/request_deletion_otp
  def request_deletion_otp
    # Verify current password first
    unless @user.valid_password?(params[:current_password])
      render json: { success: false, error: 'Invalid password. Please try again.' }
      return
    end

    begin
      # Generate 6-digit OTP
      otp = rand(100000..999999).to_s
      
      # Store OTP in session with expiration (10 minutes)
      session[:deletion_otp] = otp
      session[:deletion_otp_expires_at] = 10.minutes.from_now
      session[:deletion_verified_password] = true
      
      # Send OTP via email (you'll need to implement this mailer)
      AccountDeletionMailer.send_deletion_otp(@user, otp).deliver_now
      
      # Log the OTP request
      Rails.logger.info "Account deletion OTP requested for user: #{@user.email}"
      
      render json: { 
        success: true, 
        message: "A verification code has been sent to #{@user.email}. Please check your email and enter the 6-digit code to confirm account deletion." 
      }
    rescue => e
      Rails.logger.error "Failed to send deletion OTP: #{e.message}"
      render json: { success: false, error: 'Failed to send verification email. Please try again.' }
    end
  end

  # DELETE /settings/account
  def destroy_account
    # Verify OTP and password were provided
    unless params[:otp].present? && session[:deletion_verified_password]
      render json: { success: false, error: 'Invalid verification process. Please start over.' }
      return
    end

    # Check if OTP is expired
    if session[:deletion_otp_expires_at].nil? || Time.current > session[:deletion_otp_expires_at]
      render json: { success: false, error: 'Verification code has expired. Please request a new one.' }
      return
    end

    # Verify OTP
    unless session[:deletion_otp] == params[:otp]
      render json: { success: false, error: 'Invalid verification code. Please try again.' }
      return
    end

    user_email = @user.email

    begin
      # Start transaction to ensure data consistency
      ActiveRecord::Base.transaction do
        # Clear OTP session data
        session[:deletion_otp] = nil
        session[:deletion_otp_expires_at] = nil
        session[:deletion_verified_password] = nil

        # Delete conflict queues first (to avoid foreign key violations)
        @user.conflict_queues.destroy_all
        
        # Delete owned projects (will cascade to associated data)
        @user.owned_projects.destroy_all
        
        # Remove user from joined projects by deleting memberships completely
        @user.project_memberships.destroy_all
        
        # Delete join requests
        @user.project_join_requests.destroy_all
        
        # Delete email verifications
        @user.email_verifications.destroy_all
        
        # Send farewell email
        AccountDeletionMailer.account_deleted_confirmation(user_email).deliver_now
        
        # Log the account deletion
        Rails.logger.info "User account deleted: #{user_email}"
        
        # Delete the user account
        @user.destroy!
      end
      
      # Sign out and redirect
      sign_out(@user)
      render json: { 
        success: true, 
        message: 'Your account has been permanently deleted. We\'re sorry to see you go!',
        redirect_url: root_path
      }
      
    rescue => e
      Rails.logger.error "Failed to delete user account: #{e.message}"
      render json: { success: false, error: 'Failed to delete account. Please contact support.' }
    end
  end

  private

  def set_user
    @user = current_user
  end

  def profile_params
    params.require(:user).permit(:username)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end

  def require_current_password
    return if params[:user]&.dig(:current_password).present?
    
    redirect_to user_settings_path, alert: 'Current password is required for this action.'
  end

  # Helper method to load user projects consistently
  def load_user_projects
    @owned_projects = @user.owned_projects.includes(:users)
    
    # Get joined projects by going through project_memberships directly
    @joined_projects = Project.joins(:project_memberships)
                              .where(project_memberships: { user: @user, active: true })
                              .where.not(owner: @user)  # Explicitly exclude owned projects
                              .includes(:owner)
                              .distinct
                              
    @pending_requests = @user.project_join_requests.includes(:project)
  end

  def generate_user_data_export
    {
      user_info: {
        id: @user.id,
        username: @user.username,
        email: @user.email,
        provider: @user.provider,
        email_verified: @user.email_verified?,
        created_at: @user.created_at,
        updated_at: @user.updated_at
      },
      owned_projects: @user.owned_projects.map do |project|
        {
          id: project.id,
          name: project.name,
          slug: project.slug,
          created_at: project.created_at,
          members_count: project.project_memberships.where(active: true).count,
          members: project.users.joins(:project_memberships)
                         .where(project_memberships: { active: true })
                         .pluck(:email)
        }
      end,
      joined_projects: Project.joins(:project_memberships)
                              .where(project_memberships: { user: @user, active: true })
                              .where.not(owner: @user)  # Explicitly exclude owned projects
                              .map do |project|
        membership = @user.project_memberships.find_by(project: project, active: true)
        {
          id: project.id,
          name: project.name,
          slug: project.slug,
          owner_email: project.owner.email,
          joined_at: membership&.created_at,
          role: membership&.role,
          active: membership&.active
        }
      end,
      join_requests: @user.project_join_requests.includes(:project).map do |request|
        {
          id: request.id,
          project_name: request.project.name,
          project_slug: request.project.slug,
          status: request.status,
          requested_at: request.created_at,
          updated_at: request.updated_at
        }
      end,
      export_metadata: {
        exported_at: Time.current,
        export_version: '1.0',
        total_owned_projects: @user.owned_projects.count,
        total_joined_projects: Project.joins(:project_memberships)
                                      .where(project_memberships: { user: @user, active: true })
                                      .where.not(owner: @user)
                                      .count,
        total_join_requests: @user.project_join_requests.count
      }
    }
  end
end