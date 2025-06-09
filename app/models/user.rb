class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
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
