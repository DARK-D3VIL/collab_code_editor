class DocumentChange < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :editing_session, optional: true

  validates :file_path, presence: true
  validates :branch_name, presence: true
  validates :operation_type, presence: true, inclusion: {
    in: %w[insert delete replace merge cursor_move]
  }

  # Scopes
  scope :for_file, ->(project_id, file_path, branch_name) {
    where(project_id: project_id, file_path: file_path, branch_name: branch_name)
  }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_revision_range, ->(start_rev, end_rev) {
    where(revision: start_rev..end_rev)
  }
  scope :by_revision, -> { order(:revision) }

  # Methods
  def author_name
    user.username.presence || user.email.split("@").first
  end

  def author_color
    generate_user_color(user_id)
  end

  def as_annotation
    {
      id: id,
      user_id: user_id,
      user_name: author_name,
      user_color: author_color,
      start_line: start_line,
      end_line: end_line,
      start_column: start_column,
      end_column: end_column,
      operation_type: operation_type,
      content: content,
      revision: revision,
      operation_data: operation_data,
      timestamp: created_at.to_i,
      relative_time: ActionController::Base.helpers.time_ago_in_words(created_at)
    }
  end

  def has_position?
    start_line.present? && end_line.present?
  end

  def single_line?
    has_position? && start_line == end_line
  end

  private

  def generate_user_color(user_id)
    colors = %w[
      #FF6B6B #4ECDC4 #45B7D1 #96CEB4 #FFEAA7
      #DDA0DD #98D8C8 #F06292 #AED581 #FFD54F
    ]
    colors[user_id % colors.length]
  end
end
