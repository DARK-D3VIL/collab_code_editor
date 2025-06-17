# Create app/controllers/users/sessions_controller.rb

class Users::SessionsController < Devise::SessionsController
  # Override create to handle unverified users
  def create
    # Find user by email first
    user = User.find_by(email: params[:user][:email]) if params[:user]

    # If user exists and password is correct but email not verified
    if user && user.valid_password?(params[:user][:password]) && !user.email_verified?
      # Create or find pending verification
      verification = user.pending_email_verification
      unless verification
        verification = user.email_verifications.create!(email: user.email)
        EmailVerificationJob.perform_later(verification.id)
      end

      # Store user ID for verification process
      session[:pending_user_id] = user.id

      redirect_to email_verification_path,
                  alert: "Please verify your email address before signing in. We've sent you a new verification code."
      return
    end

    # Otherwise, let Devise handle the normal login process
    super
  end

  protected

  def configure_sign_in_params
    devise_parameter_sanitizer.permit(:sign_in, keys: [ :email ])
  end
end
