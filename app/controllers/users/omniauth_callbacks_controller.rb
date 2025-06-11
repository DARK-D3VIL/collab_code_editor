class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    auth = request.env["omniauth.auth"]
    if current_user
      current_user.update!(
        provider: auth.provider,
        uid: auth.uid,
        github_token: auth.credentials.token
      )

      redirect_to github_repos_path, notice: "GitHub account linked successfully!"
    else
      # Sign in via GitHub directly
      @user = User.find_by(provider: auth.provider, uid: auth.uid)

      if @user.nil?
        # Optional: You could also allow GitHub-only signups here
        redirect_to new_user_session_path, alert: "Please log in first before connecting GitHub."
      else
        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: "GitHub") if is_navigational_format?
      end
    end
  end

  def failure
    redirect_to root_path, alert: "GitHub authentication failed."
  end
end
