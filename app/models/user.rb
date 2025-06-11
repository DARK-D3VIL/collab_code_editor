class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
       :recoverable, :rememberable, :validatable,
       :omniauthable, omniauth_providers: [ :github ]

  def self.from_omniauth(auth)
    # Try finding by provider + uid
    user = find_by(provider: auth.provider, uid: auth.uid)

    # If not found, fallback to existing user by email
    user ||= find_by(email: auth.info.email)

    # If still not found, initialize a new user
    user ||= User.new

    # Update attributes
    user.provider = auth.provider
    user.uid = auth.uid
    user.email ||= auth.info.email
    user.username ||= auth.info.nickname
    user.password = Devise.friendly_token[0, 20] if user.encrypted_password.blank?
    user.github_token = auth.credentials.token

    # Save changes (or re-raise error)
    user.save!
    user
  end

  validates :username, presence: true

  has_many :project_memberships
  # has_many :document_changes, dependent: :destroy
  # has_many :editing_sessions, through: :document_changes
  has_many :projects, through: :project_memberships
  has_many :owned_projects, class_name: "Project", foreign_key: "owner_id"

  def membership_for(project)
    project_memberships.find_by(project_id: project.id)
  end

  def current_branch_for(project)
    membership_for(project)&.current_branch
  end
end
