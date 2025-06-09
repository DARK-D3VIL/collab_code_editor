class ProjectMembership < ApplicationRecord
  belongs_to :user
  belongs_to :project
  belongs_to :current_branch, class_name: "Branch"
end
