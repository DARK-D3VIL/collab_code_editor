# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  def email_verification(email_verification)
    @user = email_verification.user
    @verification = email_verification
    @token = email_verification.token
    @expires_at = email_verification.expires_at

    mail(
      to: @verification.email,
      subject: "Verify Your Email Address"
    )
  end
end
