# app/models/conflict_queue.rb
class ConflictQueue < ApplicationRecord
  belongs_to :project
  belongs_to :user

  validates :file_path, :branch, presence: true
  validates :conflicting_lines, presence: true
  validates :operation_type, inclusion: { in: %w[edit replace insert delete] }

  scope :unresolved, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_file, ->(project_id, file_path, branch) do
    where(project_id: project_id, file_path: file_path, branch: branch)
  end

  # Auto-expire old conflicts (older than 5 minutes)
  scope :expired, -> { where("created_at < ?", 5.minutes.ago) }
  scope :active, -> { where("created_at >= ?", 5.minutes.ago) }

  before_save :ensure_line_range

  def conflicting_lines_array
    return [] if conflicting_lines.blank?

    begin
      JSON.parse(conflicting_lines)
    rescue JSON::ParserError
      # Fallback for simple comma-separated values
      conflicting_lines.split(",").map(&:to_i).compact
    end
  end

  def conflicting_lines_array=(lines)
    self.conflicting_lines = lines.to_json
    ensure_line_range
  end

  def line_range
    lines = conflicting_lines_array
    return "N/A" if lines.empty?

    if lines.length == 1
      lines.first.to_s
    else
      "#{lines.min}-#{lines.max}"
    end
  end

  def age_in_seconds
    Time.current - created_at
  end

  def expired?
    age_in_seconds > 5.minutes
  end

  def resolve!
    update!(resolved: true, resolved_at: Time.current)
  end

  # Get current content for the conflicting lines from Redis
  def current_content_for_lines
    room_id = "editor:#{project_id}:#{branch}:#{file_path.gsub('/', ':')}"
    full_content = $redis.get("content:#{room_id}") || ""

    lines = full_content.split("\n")
    conflicting_lines_array.map do |line_num|
      line_index = line_num - 1
      line_index >= 0 && line_index < lines.length ? lines[line_index] : "(empty line)"
    end
  end

  # Class methods for conflict management
  class << self
    # Clean up expired conflicts
    def cleanup_expired!
      expired_count = expired.delete_all
      Rails.logger.info "Cleaned up #{expired_count} expired conflicts" if expired_count > 0
      expired_count
    end

    # Create conflict for a specific operation
    def create_for_operation!(project_id:, user_id:, file_path:, branch:, operation_type:, conflicting_lines:)
      # Ensure we have valid line numbers
      lines = Array(conflicting_lines).compact.uniq.sort
      return nil if lines.empty?

      create!(
        project_id: project_id,
        user_id: user_id,
        file_path: file_path,
        branch: branch,
        operation_type: operation_type,
        line_start: lines.min,
        line_end: lines.max,
        conflicting_lines: lines.to_json,
        resolved: false
      )
    end

    # Auto-resolve conflicts when lines are successfully merged
    def resolve_conflicts_for_lines(project_id, file_path, branch, lines)
      resolved_count = 0

      where(
        project_id: project_id,
        file_path: file_path,
        branch: branch,
        resolved: false
      ).find_each do |conflict|
        conflict_lines = conflict.conflicting_lines_array

        # If any of the resolved lines overlap with conflict lines, resolve it
        if (conflict_lines & Array(lines)).any?
          conflict.resolve!
          resolved_count += 1
        end
      end

      Rails.logger.info "Auto-resolved #{resolved_count} conflicts for lines #{lines}" if resolved_count > 0
      resolved_count
    end

    # Get conflicts for a specific user and file
    def for_user_and_file(user_id, project_id, file_path, branch)
      unresolved
        .where(
          user_id: user_id,
          project_id: project_id,
          file_path: file_path,
          branch: branch
        )
        .recent
    end

    # Check if lines have active conflicts
    def lines_have_conflicts?(project_id, file_path, branch, lines)
      return false if lines.blank?

      unresolved
        .active
        .where(project_id: project_id, file_path: file_path, branch: branch)
        .any? do |conflict|
          conflict_lines = conflict.conflicting_lines_array
          (conflict_lines & Array(lines)).any?
        end
    end

    # Get all conflicting users for specific lines
    def conflicting_users_for_lines(project_id, file_path, branch, lines, exclude_user_id: nil)
      return [] if lines.blank?

      conflicts = unresolved
                    .active
                    .where(project_id: project_id, file_path: file_path, branch: branch)
                    .includes(:user)

      conflicts = conflicts.where.not(user_id: exclude_user_id) if exclude_user_id

      conflicting_users = []

      conflicts.each do |conflict|
        conflict_lines = conflict.conflicting_lines_array
        overlapping_lines = conflict_lines & Array(lines)

        if overlapping_lines.any?
          conflicting_users << {
            user: conflict.user,
            conflict_id: conflict.id,
            lines: overlapping_lines,
            age: conflict.age_in_seconds
          }
        end
      end

      conflicting_users.uniq { |cu| cu[:user].id }
    end

    # Bulk create conflicts for multiple users
    def create_bulk_conflicts!(conflicts_data)
      created_conflicts = []

      conflicts_data.each do |data|
        begin
          conflict = create_for_operation!(
            project_id: data[:project_id],
            user_id: data[:user_id],
            file_path: data[:file_path],
            branch: data[:branch],
            operation_type: data[:operation_type] || "edit",
            conflicting_lines: data[:lines]
          )
          created_conflicts << conflict if conflict
        rescue => e
          Rails.logger.error "Failed to create conflict for user #{data[:user_id]}: #{e.message}"
        end
      end

      created_conflicts
    end
  end

  private

  def ensure_line_range
    lines = conflicting_lines_array
    if lines.any?
      self.line_start = lines.min
      self.line_end = lines.max
    end
  end
end

# Background job for cleaning up expired conflicts
# app/jobs/cleanup_expired_conflicts_job.rb
class CleanupExpiredConflictsJob < ApplicationJob
  queue_as :default

  def perform
    ConflictQueue.cleanup_expired!
  end
end
