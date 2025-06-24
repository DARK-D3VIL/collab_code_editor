# app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules
  devise :database_authenticatable, :registerable,
       :recoverable, :rememberable, :validatable,
       :omniauthable, omniauth_providers: [ :github ]

  # Associations
  has_many :email_verifications, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships
  has_many :owned_projects, class_name: "Project", foreign_key: "owner_id", dependent: :destroy
  has_many :project_join_requests, dependent: :destroy
  has_many :ai_training_jobs, dependent: :destroy

  validates :username, presence: true

  # GitHub OAuth method
  def self.from_omniauth(auth)
    email = auth.info.email
    github_uid = auth.uid
    github_token = auth.credentials.token
    provider = auth.provider

    # Match by UID and provider (user has already connected GitHub)
    user = find_by(provider: provider, uid: github_uid)

    if user
      user.update!(github_token: github_token) # refresh token if needed
      return user
    end

    # If not found, check if user with same email exists
    user = find_by(email: email)

    if user
      # Prevent GitHub signup if email is already used
      raise Devise::OmniauthCallbacksController::AccountTakenError.new("Email already associated with an account. Please sign in manually and connect GitHub from settings.")
    end

    # Otherwise, create new user with GitHub data
    create!(
      provider: provider,
      uid: github_uid,
      email: email,
      username: auth.info.nickname,
      password: Devise.friendly_token[0, 20],
      github_token: github_token,
      email_verified_at: Time.current # GitHub users are auto-verified
    )
  end

  # Email verification methods
  def email_verified?
    email_verified_at.present?
  end

  def pending_email_verification
    email_verifications.active.first
  end

  def verify_email_with_token(token)
    verification = email_verifications.active.find_by(token: token)
    return false unless verification
    verification.verify!
  end

  # Override active_for_authentication to prevent login without verification
  def active_for_authentication?
    super && (email_verified? || oauth_user?)
  end

  # Custom message for inactive users
  def inactive_message
    email_verified? ? super : :email_not_verified
  end

  # Check if user signed up via OAuth
  def oauth_user?
    provider.present? && uid.present?
  end

  # Existing methods
  def membership_for(project)
    project_memberships.find_by(project_id: project.id)
  end

  def current_branch_for(project)
    membership_for(project)&.current_branch
  end

  def accessible_projects
    Project
      .left_outer_joins(:project_memberships)
      .where(
        "projects.owner_id = :id OR (project_memberships.user_id = :id AND project_memberships.active = :active)",
        id: id,
        active: true
      ).distinct
  end

  def github_token_valid?
    return false unless github_token.present?

    begin
      response = Faraday.get("https://api.github.com/user", {}, {
        Authorization: "token #{github_token}",
        Accept: "application/vnd.github+json"
      })
      response.success?
    rescue
      false
    end
  end
end
