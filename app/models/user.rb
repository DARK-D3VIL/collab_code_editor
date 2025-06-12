class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
       :recoverable, :rememberable, :validatable,
       :omniauthable, omniauth_providers: [ :github ]

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

    # If not found, check if user with same email exists (manual sign-up or different OAuth)
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
      github_token: github_token
    )
  end

  validates :username, presence: true

  has_many :project_memberships
  has_many :projects, through: :project_memberships
  has_many :owned_projects, class_name: "Project", foreign_key: "owner_id"

  def membership_for(project)
    project_memberships.find_by(project_id: project.id)
  end

  def current_branch_for(project)
    membership_for(project)&.current_branch
  end
end
