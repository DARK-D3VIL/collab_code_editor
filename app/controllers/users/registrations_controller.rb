# Update your app/controllers/users/registrations_controller.rb

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_permitted_parameters
  before_action :find_pending_user, only: [ :email_verification, :verify_email, :resend_verification ]

  def create
    build_resource(sign_up_params)

    if resource.save
      # Create the email verification record FIRST
      verification = resource.email_verifications.create!(email: resource.email)

      # Then queue the email job with the verification ID
      EmailVerificationJob.perform_later(verification.id)

      # Store user ID in session for verification process
      session[:pending_user_id] = resource.id

      redirect_to email_verification_path, notice: "Please check your email for the verification code."
    else
      clean_up_passwords resource
      set_minimum_password_length
      render :new, status: :unprocessable_entity
    end
  end

  # Email verification page
  def email_verification
    return redirect_to_appropriate_page unless @user

    @verification = @user.pending_email_verification

    unless @verification
      redirect_to new_user_registration_path, alert: "Verification expired. Please sign up again."
    else
      # Render from devise/registrations to match your existing view structure
      render "devise/registrations/email_verification"
    end
  end

  # Verify email with token
  def verify_email
    return redirect_to_appropriate_page unless @user

    if @user.verify_email_with_token(params[:token])
      session.delete(:pending_user_id)
      sign_in(@user)
      redirect_to root_path, notice: "Email verified successfully! Welcome!"
    else
      @verification = @user.pending_email_verification
      if @verification
        flash.now[:alert] = "Invalid or expired verification code."
        render "devise/registrations/email_verification", status: :unprocessable_entity
      else
        redirect_to new_user_registration_path, alert: "Verification expired. Please sign up again."
      end
    end
  end

  # Resend verification email
  def resend_verification
    return redirect_to_appropriate_page unless @user

    verification = @user.pending_email_verification
    if verification
      # Queue another email job using the existing verification
      EmailVerificationJob.perform_later(verification.id)
      redirect_to email_verification_path, notice: "Verification code sent again."
    else
      # Create new verification if none exists
      verification = @user.email_verifications.create!(email: @user.email)
      EmailVerificationJob.perform_later(verification.id)
      redirect_to email_verification_path, notice: "New verification code sent."
    end
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :username ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :username ])
  end

  private

  def find_pending_user
    # First check session, then check if current user needs verification
    @user = User.find_by(id: session[:pending_user_id])

    # If no user in session but someone is signed in and unverified, use them
    if @user.nil? && user_signed_in? && !current_user.email_verified?
      @user = current_user
      session[:pending_user_id] = @user.id
    end
  end

  def redirect_to_appropriate_page
    if @user.nil?
      redirect_to new_user_registration_path, alert: "Session expired. Please sign up again."
      return false
    elsif @user.email_verified?
      redirect_to root_path, notice: "Account already verified."
      return false
    end
    true
  end
end
