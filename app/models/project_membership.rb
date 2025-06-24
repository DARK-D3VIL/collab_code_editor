class ProjectMembership < ApplicationRecord
  belongs_to :user
  belongs_to :project
  belongs_to :current_branch, class_name: "Branch", optional: true # Make optional in case no branch selected yet

  # Add the role enum
  enum role: { reader: 0, writer: 1 }

  # Add helper methods
  def can_write?
    writer?
  end

  def is_owner?
    project.owner_id == user_id
  end

  # Add scopes for common queries
  scope :active_members, -> { where(active: true) }
  scope :readers, -> { where(role: :reader) }
  scope :writers, -> { where(role: :writer) }
end
