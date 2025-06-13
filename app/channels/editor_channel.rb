class EditorChannel < ApplicationCable::Channel
  # Use class variables to store active editors in memory
  @@active_editors = {}
  @@recent_edits = {}
  @@user_content = {}  # Store each user's current content
  @@live_content = {}  # Store the most recent live content for each file
  @@mutex = Mutex.new

  def subscribed
    @project_id = params[:project_id]
    @file_id = params[:file_id]
    @branch = params[:branch]
    @user_id = current_user.id

    @stream_key = "editor_#{@project_id}_#{@branch}_#{@file_id}"
    @active_key = active_editors_key
    @live_content_key = live_content_key

    stream_from @stream_key
    stream_for current_user # for private conflict notifications

    # Check if this is the first user (session restart scenario)
    is_first_user = fetch_all_active_users.empty?

    # Add user to active editors when they subscribe
    add_to_active_editors(@user_id)

    # Only send live content if there were already active users
    # If this is the first user after cleanup, they should get initial content
    unless is_first_user
      send_current_live_content_to_user
    end

    Rails.logger.info "[EditorChannel] User #{@user_id} subscribed to #{@stream_key}"
    Rails.logger.info "[EditorChannel] Is first user: #{is_first_user}"
    Rails.logger.info "[EditorChannel] Active editors after subscription: #{fetch_all_active_users.inspect}"
  end

  def unsubscribed
    # Remove user from active editors when they disconnect
    remove_from_active_editors(@user_id)
    Rails.logger.info "[EditorChannel] User #{@user_id} unsubscribed from #{@stream_key}"
  end

  def receive(data)
    changed_lines = (data["changed_lines"] || {}).transform_keys(&:to_i)
    base_content = data["base_content"] || ""
    incoming_content = data["content"] || ""
    incoming_user_id = @user_id

    Rails.logger.info "[EditorChannel] Received data from user #{incoming_user_id}"
    Rails.logger.info "[EditorChannel] Changed lines: #{changed_lines.inspect}"

    # Store user's current content BEFORE processing conflicts
    store_user_content(incoming_user_id, incoming_content)

    # Update the live content for this file
    update_live_content(incoming_content)

    # Ensure this user is in active editors (in case subscription was missed)
    add_to_active_editors(incoming_user_id)

    # Get all active users editing this file
    all_active_users = fetch_all_active_users
    other_users = all_active_users - [ incoming_user_id ]

    Rails.logger.info "[EditorChannel] All active users: #{all_active_users.inspect}"
    Rails.logger.info "[EditorChannel] Other users to check: #{other_users.inspect}"

    # Check for conflicts with other users BEFORE tracking new edits
    other_users.each do |other_user_id|
      check_and_handle_conflicts(other_user_id, incoming_user_id, changed_lines, incoming_content, base_content)
    end

    # Track this user's edits AFTER checking conflicts
    track_user_edits(incoming_user_id, changed_lines.keys.map(&:to_i), changed_lines)

    # Broadcast changes to all users
    ActionCable.server.broadcast(@stream_key, {
      sender_id: incoming_user_id,
      changed_lines: changed_lines,
      content: incoming_content,
      timestamp: Time.current.to_f
    })
  end

  private

  def send_current_live_content_to_user
    live_content = get_live_content
    if live_content && !live_content.empty?
      # Send the live content directly to this user
      transmit({
        type: "live_content_sync",
        content: live_content,
        timestamp: Time.current.to_f
      })
      Rails.logger.info "[EditorChannel] Sent live content to newly joined user #{@user_id}"
    else
      Rails.logger.info "[EditorChannel] No live content available for user #{@user_id}, using initial content"
    end
  end

  def update_live_content(content)
    @@mutex.synchronize do
      @@live_content[@live_content_key] = content
      Rails.logger.info "[EditorChannel] Updated live content for #{@live_content_key}"
    end
  end

  def get_live_content
    @@mutex.synchronize do
      @@live_content[@live_content_key]
    end
  end

  def check_and_handle_conflicts(other_user_id, incoming_user_id, changed_lines, incoming_content, base_content)
    recent_edits = get_user_recent_edits(other_user_id)
    Rails.logger.info "[Conflict Check] Checking conflicts for user #{other_user_id}"
    Rails.logger.info "[Conflict Check] Recent edits for user #{other_user_id}: #{recent_edits.keys.inspect}"
    Rails.logger.info "[Conflict Check] Incoming changes from user #{incoming_user_id}: #{changed_lines.keys.inspect}"

    # Find conflicting lines (lines that both users have edited recently)
    conflict_lines = changed_lines.keys.map(&:to_i) & recent_edits.keys.map(&:to_i)
    Rails.logger.info "[Conflict Check] Conflict lines: #{conflict_lines.inspect}"

    if conflict_lines.any?
      Rails.logger.info "[Conflict Detected] Creating conflict for user #{other_user_id} on lines #{conflict_lines}"

      # Get the other user's current content to show proper diff
      other_user_content = get_user_content(other_user_id)
      other_user_lines = other_user_content.split("\n")
      incoming_lines = incoming_content.split("\n")

      # Prepare conflict data for each conflicting line
      conflicting_line_data = {}
      conflict_lines.each do |line_num|
        line_index = line_num - 1 # Convert to 0-based index
        conflicting_line_data[line_num.to_s] = {
          "incoming" => incoming_lines[line_index] || "",
          "existing" => other_user_lines[line_index] || ""
        }
      end

      # Create conflict record
      conflict = ConflictQueue.create!(
        project_id: @project_id,
        user_id: other_user_id,
        file_path: @file_id,
        branch: @branch,
        content: incoming_content,
        base_content: base_content,
        lines_changed: conflict_lines,
        changed_lines: conflicting_line_data,
        incoming_content: incoming_content,
        resolved: false
      )

      Rails.logger.info "[Conflict Created] Conflict ID: #{conflict.id} for user #{other_user_id}"

      # Notify the affected user about the conflict
      EditorChannel.broadcast_to(User.find(other_user_id), {
        type: "conflict",
        conflict: true,
        file_path: @file_id,
        lines_changed: conflict_lines,
        conflict_id: conflict.id
      })

      Rails.logger.info "[Conflict Broadcast] Sent conflict notification to user #{other_user_id}"
    else
      Rails.logger.info "[No Conflict] No conflicting lines found between users #{incoming_user_id} and #{other_user_id}"
    end
  end

  def store_user_content(user_id, content)
    @@mutex.synchronize do
      content_key = user_content_key(user_id)
      @@user_content[content_key] = content
      Rails.logger.info "[EditorChannel] Stored content for user #{user_id}"
    end
  end

  def get_user_content(user_id)
    @@mutex.synchronize do
      content_key = user_content_key(user_id)
      @@user_content[content_key] || ""
    end
  end

  def fetch_all_active_users
    @@mutex.synchronize do
      editors = @@active_editors[@active_key] || []
      Rails.logger.info "[EditorChannel] Fetching active editors for key: #{@active_key}"
      Rails.logger.info "[EditorChannel] Active editors: #{editors.inspect}"
      editors.dup # Return a copy to avoid external modification
    end
  end

  def add_to_active_editors(user_id)
    @@mutex.synchronize do
      Rails.logger.info "[EditorChannel] Adding user #{user_id} with key: #{@active_key}"

      @@active_editors[@active_key] ||= []

      unless @@active_editors[@active_key].include?(user_id)
        @@active_editors[@active_key] << user_id
        Rails.logger.info "[EditorChannel] Added user #{user_id} to active editors: #{@@active_editors[@active_key].inspect}"
      else
        Rails.logger.info "[EditorChannel] User #{user_id} already in active editors: #{@@active_editors[@active_key].inspect}"
      end

      # Verify the addition worked
      Rails.logger.info "[EditorChannel] Verification - active editors now: #{@@active_editors[@active_key].inspect}"
    end
  end

  def remove_from_active_editors(user_id)
    @@mutex.synchronize do
      Rails.logger.info "[EditorChannel] Removing user #{user_id} with key: #{@active_key}"

      if @@active_editors[@active_key]
        @@active_editors[@active_key].delete(user_id)
        Rails.logger.info "[EditorChannel] Removed user #{user_id} from active editors: #{@@active_editors[@active_key].inspect}"

        # Clean up when no active editors remain
        if @@active_editors[@active_key].empty?
          Rails.logger.info "[EditorChannel] No active editors remaining, cleaning up session data"
          cleanup_session_data
          @@active_editors.delete(@active_key)
        end
      else
        Rails.logger.info "[EditorChannel] No active editors found for key: #{@active_key}"
      end
    end

    # Clean up user's data when they disconnect
    cleanup_user_data(user_id)
  end

  def track_user_edits(user_id, line_numbers, changed_lines_content)
    return if line_numbers.empty?

    @@mutex.synchronize do
      now = Time.current.to_f
      edit_key = recent_edit_key(user_id)

      @@recent_edits[edit_key] ||= {}

      line_numbers.each do |ln|
        @@recent_edits[edit_key][ln] = {
          timestamp: now,
          content: changed_lines_content[ln] || ""
        }
      end

      Rails.logger.info "[EditorChannel] Tracked edits for user #{user_id} on lines: #{line_numbers.inspect}"
      Rails.logger.info "[EditorChannel] User #{user_id} recent edits now: #{@@recent_edits[edit_key].keys.inspect}"

      # Clean up old edits (older than 2 minutes)
      cutoff_time = now - 120 # 2 minutes ago
      @@recent_edits[edit_key].delete_if { |line, data| data[:timestamp] < cutoff_time }
    end
  end

  def get_user_recent_edits(user_id)
    @@mutex.synchronize do
      edit_key = recent_edit_key(user_id)
      recent_edits = @@recent_edits[edit_key] || {}

      # Clean up old edits (older than 2 minutes)
      now = Time.current.to_f
      cutoff_time = now - 120 # 2 minutes ago
      recent_edits.delete_if { |line, data| data[:timestamp] < cutoff_time }

      # Return just the line numbers for conflict checking
      recent_edits.transform_values { |data| data[:timestamp] }
    end
  end

  def cleanup_user_data(user_id)
    @@mutex.synchronize do
      edit_key = recent_edit_key(user_id)
      content_key = user_content_key(user_id)

      @@recent_edits.delete(edit_key)
      @@user_content.delete(content_key)

      Rails.logger.info "[EditorChannel] Cleaned up data for user #{user_id}"
    end
  end

  def cleanup_session_data
    # This method cleans up all session-related data when no users are active
    # Called from remove_from_active_editors when the last user leaves

    Rails.logger.info "[EditorChannel] Cleaning up session data for #{@live_content_key}"

    # Remove live content so next user gets fresh initial content
    @@live_content.delete(@live_content_key)

    # Clean up all recent edits and user content for this file/branch
    keys_to_delete = []

    @@recent_edits.each_key do |key|
      if key.include?("file_#{@file_id}_branch_#{@branch}")
        keys_to_delete << key
      end
    end

    @@user_content.each_key do |key|
      if key.include?("file_#{@file_id}_branch_#{@branch}")
        keys_to_delete << key
      end
    end

    keys_to_delete.each do |key|
      @@recent_edits.delete(key)
      @@user_content.delete(key)
    end

    Rails.logger.info "[EditorChannel] Session cleanup completed. Removed #{keys_to_delete.length} keys"
    Rails.logger.info "[EditorChannel] Next user will start with initial content from server"
  end

  def active_editors_key
    "active_editors_#{@project_id}_#{@branch}_#{@file_id}"
  end

  def recent_edit_key(user_id)
    "recent_edits_user_#{user_id}_file_#{@file_id}_branch_#{@branch}"
  end

  def user_content_key(user_id)
    "user_content_#{user_id}_file_#{@file_id}_branch_#{@branch}"
  end

  def live_content_key
    "live_content_#{@project_id}_#{@branch}_#{@file_id}"
  end

  # Class methods for conflict resolution
  def self.update_live_content_for_file(project_id, branch, file_id, content)
    live_content_key = "live_content_#{project_id}_#{branch}_#{file_id}"

    @@mutex.synchronize do
      @@live_content[live_content_key] = content
      Rails.logger.info "[EditorChannel] Updated live content externally for #{live_content_key}"
    end
  end

  def self.get_user_content_for_conflict(project_id, branch, file_id, user_id)
    user_content_key = "user_content_#{user_id}_file_#{file_id}_branch_#{branch}"

    @@mutex.synchronize do
      content = @@user_content[user_content_key]
      Rails.logger.info "[EditorChannel] Retrieved user content for conflict: #{user_content_key} - #{content ? 'found' : 'not found'}"
      content
    end
  end

  # Class method to inspect current state (useful for debugging)
  def self.debug_state
    Rails.logger.info "[EditorChannel Debug] Active editors: #{@@active_editors.inspect}"
    Rails.logger.info "[EditorChannel Debug] Recent edits: #{@@recent_edits.inspect}"
    Rails.logger.info "[EditorChannel Debug] User content keys: #{@@user_content.keys.inspect}"
    Rails.logger.info "[EditorChannel Debug] Live content keys: #{@@live_content.keys.inspect}"
  end

  # Class method to clean up stale data
  def self.cleanup_stale_data
    @@mutex.synchronize do
      now = Time.current.to_f
      cutoff_time = now - 120 # 2 minutes ago

      @@recent_edits.each do |key, edits|
        edits.delete_if { |line, data| data[:timestamp] < cutoff_time }
        @@recent_edits.delete(key) if edits.empty?
      end
    end
  end

  # Class method to force cleanup of inactive sessions
  def self.cleanup_inactive_sessions
    @@mutex.synchronize do
      Rails.logger.info "[EditorChannel] Starting cleanup of inactive sessions"

      # Find active editor keys that have no active users
      inactive_keys = []
      @@active_editors.each do |key, users|
        if users.empty?
          inactive_keys << key
        end
      end

      # Clean up each inactive session
      inactive_keys.each do |key|
        Rails.logger.info "[EditorChannel] Cleaning up inactive session: #{key}"

        # Extract file and branch info from key
        if key.match(/active_editors_(\d+)_(.+)_(.+)/)
          project_id, branch, file_id = $1, $2, $3
          live_content_key = "live_content_#{project_id}_#{branch}_#{file_id}"

          # Remove live content
          @@live_content.delete(live_content_key)

          # Remove related user data
          @@recent_edits.delete_if { |k, v| k.include?("file_#{file_id}_branch_#{branch}") }
          @@user_content.delete_if { |k, v| k.include?("file_#{file_id}_branch_#{branch}") }
        end

        # Remove the active editors key
        @@active_editors.delete(key)
      end

      Rails.logger.info "[EditorChannel] Cleaned up #{inactive_keys.length} inactive sessions"
    end
  end
end
