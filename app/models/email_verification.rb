# Replace your app/models/email_verification.rb with this:

class EmailVerification < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :email, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  # Generate token before validation (not before_create)
  before_validation :generate_token, on: :create

  # Token expires in 10 minutes
  TOKEN_EXPIRY = 10.minutes

  def self.cleanup_expired
    expired.delete_all
  end

  def expired?
    expires_at < Time.current
  end

  def active?
    !expired?
  end

  def verify!
    return false if expired?

    ActiveRecord::Base.transaction do
      user.update!(email_verified_at: Time.current)
      destroy!
    end
    true
  end

  private

  def generate_token
    return if token.present? # Don't regenerate if already set

    self.token = rand(100_000..999_999).to_s
    self.expires_at = TOKEN_EXPIRY.from_now
  end
end
