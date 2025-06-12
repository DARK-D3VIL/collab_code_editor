class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    auth = request.env["omniauth.auth"]

    begin
      @user = User.from_omniauth(auth)
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "GitHub") if is_navigational_format?
    rescue Devise::OmniauthCallbacksController::AccountTakenError => e
      redirect_to new_user_session_path, alert: e.message
    rescue => e
      Rails.logger.error "GitHub OAuth error: #{e.message}"
      redirect_to root_path, alert: "GitHub sign in failed. Please try again."
    end
  end

  def failure
    redirect_to root_path, alert: "GitHub authentication failed."
  end
end
