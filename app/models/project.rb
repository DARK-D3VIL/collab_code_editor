class Project < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  has_many :branches, dependent: :destroy
  has_many :files, class_name: "ProjectFile", dependent: :destroy
end
