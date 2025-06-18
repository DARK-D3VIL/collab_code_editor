# app/mailers/account_deletion_mailer.rb
class AccountDeletionMailer < ApplicationMailer
  def send_deletion_otp(user, otp)
    @user = user
    @otp = otp
    @expires_in = 10 # minutes
    
    mail(
      to: @user.email,
      subject: '🔐 Account Deletion Verification Code'
    )
  end

  def account_deleted_confirmation(email)
    @email = email
    @deleted_at = Time.current
    
    mail(
      to: email,
      subject: '👋 Account Successfully Deleted'
    )
  end
end