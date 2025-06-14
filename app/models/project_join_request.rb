class ProjectJoinRequest < ApplicationRecord
  belongs_to :user
  belongs_to :project

  enum status: { pending: 0 } # Only pending status needed

  validates :user_id, uniqueness: { scope: :project_id }

  scope :pending, -> { where(status: :pending) }

  def approve!
    transaction do
      destroy
    end
  end

  def reject!
    destroy
  end
end
