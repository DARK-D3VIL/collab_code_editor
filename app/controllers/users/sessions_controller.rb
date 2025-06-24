# app/controllers/users/sessions_controller.rb

class Users::SessionsController < Devise::SessionsController
  prepend_before_action :check_captcha, only: [:create]
  
  # Override create to handle unverified users
  def create
    # Find user by email first
    user = User.find_by(email: params[:user][:email]) if params[:user] && params[:user][:email]

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
    devise_parameter_sanitizer.permit(:sign_in, keys: [:email])
  end

  private

  def check_captcha
    # Only check captcha for POST requests with user params
    return true unless request.post? && params[:user].present?
    
    # Debug logging
    Rails.logger.info "=== Login reCAPTCHA Debug ==="
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
    if params['g-recaptcha-response-data'].present? && params['g-recaptcha-response-data']['login'].present?
      recaptcha_token = params['g-recaptcha-response-data']['login']
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
    
    # Verify with Google's API manually
    verification_result = verify_recaptcha_manually(recaptcha_token, 'login')
    
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
    # Build the resource for validation only if we have user params
    if params[:user].present?
      self.resource = resource_class.new sign_in_params
      
      # Add reCAPTCHA error to the resource
      resource.errors.add(:base, "reCAPTCHA verification failed. Please try again.")
    end
    
    # Set flash message
    flash.now[:alert] = "reCAPTCHA verification failed. Please try again."
    
    # Render the new template with errors
    render :new, status: :unprocessable_entity
  end

  def sign_in_params
    if params[:user].present?
      params.require(:user).permit(:email, :password, :remember_me)
    else
      {}
    end
  end
end