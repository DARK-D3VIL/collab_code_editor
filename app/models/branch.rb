class Branch < ApplicationRecord
  belongs_to :project
  belongs_to :creator, class_name: "User", foreign_key: "created_by"
  has_many :commits, dependent: :destroy
  has_many :project_memberships, foreign_key: :current_branch_id, dependent: :destroy

  validates :name, presence: true
end
