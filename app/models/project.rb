class Project < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships

  # Add the new association for join requests
  has_many :project_join_requests, dependent: :destroy
  has_many :pending_requests, -> { pending }, class_name: "ProjectJoinRequest"

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  has_many :branches, dependent: :destroy
  has_many :files, class_name: "ProjectFile", dependent: :destroy
  has_many :conflict_queues, dependent: :destroy

  # Add permission checking method
  def can_user_access?(user, permission = :read)
    return true if owner_id == user.id # Owner has all permissions

    membership = project_memberships.find_by(user: user, active: true)
    return false unless membership

    case permission
    when :read then true # All active members can read
    when :write then membership.writer?
    when :manage then false # Only owner can manage (handled above)
    else false
    end
  end

  # Helper method to check for pending requests
  def has_pending_request?(user)
    project_join_requests.pending.exists?(user: user)
  end
end
