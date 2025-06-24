# app/controllers/users/registrations_controller.rb

class Users::RegistrationsController < Devise::RegistrationsController
  prepend_before_action :check_captcha, only: [:create]
  before_action :configure_permitted_parameters
  before_action :find_pending_user, only: [:email_verification, :verify_email, :resend_verification]

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
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username])
  end

  private

  def check_captcha
    # Debug logging
    Rails.logger.info "=== reCAPTCHA Debug ==="
    Rails.logger.info "Standard reCAPTCHA token: #{params['g-recaptcha-response']}"
    Rails.logger.info "reCAPTCHA v3 data: #{params['g-recaptcha-response-data']}"
    Rails.logger.info "Site key: #{ENV['RECAPTCHA_SITE_KEY']}"
    Rails.logger.info "Secret key present: #{ENV['RECAPTCHA_SECRET_KEY'].present?}"
    
    # Check if we should skip reCAPTCHA (for development)
    if Rails.env.development? && ENV['SKIP_RECAPTCHA'] == 'true'
      Rails.logger.info "Skipping reCAPTCHA in development"
      return true
    end
    
    # Get the reCAPTCHA token from v3 response data
    recaptcha_token = nil
    if params['g-recaptcha-response-data'].present? && params['g-recaptcha-response-data']['signup'].present?
      recaptcha_token = params['g-recaptcha-response-data']['signup']
    elsif params['g-recaptcha-response'].present?
      recaptcha_token = params['g-recaptcha-response']
    end
    
    Rails.logger.info "Using reCAPTCHA token: #{recaptcha_token.present? ? 'Present' : 'Missing'}"
    
    # If no token, fail
    unless recaptcha_token.present?
      Rails.logger.error "No reCAPTCHA token found"
      handle_captcha_failure
      return false
    end
    
    # Verify with Google's API manually since the gem might have issues with v3
    verification_result = verify_recaptcha_manually(recaptcha_token, 'signup')
    
    if verification_result[:success]
      Rails.logger.info "reCAPTCHA verification successful"
      return true
    else
      Rails.logger.error "reCAPTCHA verification failed: #{verification_result[:error]}"
      handle_captcha_failure
      return false
    end
  end

  def verify_recaptcha_manually(token, action)
    require 'net/http'
    require 'json'
    
    uri = URI('https://www.google.com/recaptcha/api/siteverify')
    response = Net::HTTP.post_form(uri, {
      'secret' => ENV['RECAPTCHA_SECRET_KEY'],
      'response' => token,
      'remoteip' => request.remote_ip
    })
    
    result = JSON.parse(response.body)
    Rails.logger.info "Google reCAPTCHA response: #{result}"
    
    if result['success']
      score = result['score']
      returned_action = result['action']
      
      Rails.logger.info "reCAPTCHA score: #{score}"
      Rails.logger.info "reCAPTCHA action: #{returned_action}"
      
      # Check score (for v3, should be > 0.5)
      if score && score >= 0.5
        { success: true, score: score }
      else
        { success: false, error: "Score too low: #{score}" }
      end
    else
      { success: false, error: result['error-codes'] || 'Unknown error' }
    end
  rescue => e
    Rails.logger.error "reCAPTCHA verification error: #{e.message}"
    { success: false, error: e.message }
  end

  def handle_captcha_failure
    # Build the resource for validation
    self.resource = resource_class.new sign_up_params
    resource.validate # Look for any other validation errors besides reCAPTCHA
    set_minimum_password_length
    
    # Add reCAPTCHA error to the resource
    resource.errors.add(:base, "reCAPTCHA verification failed. Please try again.")
    
    # Set flash message
    flash.now[:alert] = "reCAPTCHA verification failed. Please try again."
    
    # Render the new template with errors
    render :new, status: :unprocessable_entity
  end

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