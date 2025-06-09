class Commit < ApplicationRecord
  belongs_to :user
  belongs_to :branch
  belongs_to :project

  validates :sha, presence: true, uniqueness: true
  validates :message, presence: true
end
