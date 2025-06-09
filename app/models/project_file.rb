class ProjectFile < ApplicationRecord
  belongs_to :project
  validates :name, :path, :language, presence: true
end
