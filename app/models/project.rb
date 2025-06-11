class Project < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships
  # has_many :editing_sessions, dependent: :destroy
  # has_many :document_changes, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  has_many :branches, dependent: :destroy
  has_many :files, class_name: "ProjectFile", dependent: :destroy
end
