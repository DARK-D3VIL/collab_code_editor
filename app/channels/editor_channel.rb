class EditorChannel < ApplicationCable::Channel
  # Use class variables to store active editors in memory
  # This works better than Rails.cache for ActionCable channels
  @@active_editors = {}
  @@recent_edits = {}
  @@mutex = Mutex.new

  def subscribed
    @project_id = params[:project_id]
    @file_id = params[:file_id]
    @branch = params[:branch]
    @user_id = current_user.id

    @stream_key = "editor_#{@project_id}_#{@branch}_#{@file_id}"
    @active_key = active_editors_key

    stream_from @stream_key
    stream_for current_user # for private conflict notifications

    # Add user to active editors when they subscribe
    add_to_active_editors(@user_id)
    Rails.logger.info "[EditorChannel] User #{@user_id} subscribed to #{@stream_key}"
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

    # Ensure this user is in active editors (in case subscription was missed)
    add_to_active_editors(incoming_user_id)

    # Get all active users editing this file
    all_active_users = fetch_all_active_users
    other_users = all_active_users - [ incoming_user_id ]

    Rails.logger.info "[EditorChannel] All active users: #{all_active_users.inspect}"
    Rails.logger.info "[EditorChannel] Other users to check: #{other_users.inspect}"

    # Track this user's edits BEFORE checking conflicts
    track_user_edits(incoming_user_id, changed_lines.keys.map(&:to_i))

    # Check for conflicts with other users
    other_users.each do |other_user_id|
      check_and_handle_conflicts(other_user_id, incoming_user_id, changed_lines, incoming_content, base_content)
    end

    # Broadcast changes to all users
    ActionCable.server.broadcast(@stream_key, {
      sender_id: incoming_user_id,
      changed_lines: changed_lines,
      content: incoming_content,
      timestamp: Time.current.to_f
    })
  end

  private

  def check_and_handle_conflicts(other_user_id, incoming_user_id, changed_lines, incoming_content, base_content)
    recent_edits = get_user_recent_edits(other_user_id)
    Rails.logger.info "[Conflict Check] Checking conflicts for user #{other_user_id}"
    Rails.logger.info "[Conflict Check] Recent edits for user #{other_user_id}: #{recent_edits.inspect}"
    Rails.logger.info "[Conflict Check] Incoming changes from user #{incoming_user_id}: #{changed_lines.keys.inspect}"

    # Find conflicting lines (lines that both users have edited recently)
    conflict_lines = changed_lines.keys.map(&:to_i) & recent_edits.keys.map(&:to_i)
    Rails.logger.info "[Conflict Check] Conflict lines: #{conflict_lines.inspect}"

    if conflict_lines.any?
      Rails.logger.info "[Conflict Detected] Creating conflict for user #{other_user_id} on lines #{conflict_lines}"

      # Prepare conflict data for each conflicting line
      conflicting_line_data = {}
      conflict_lines.each do |line_num|
        conflicting_line_data[line_num.to_s] = {
          "incoming" => changed_lines[line_num] || "",
          "existing" => get_user_line_content(other_user_id, line_num) || ""
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

  def get_user_line_content(user_id, line_num)
    # This is a simplified version - in reality you might want to store
    # the actual content of lines that users are editing
    "Line #{line_num} content for user #{user_id}"
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

        # Clean up empty arrays
        @@active_editors.delete(@active_key) if @@active_editors[@active_key].empty?
      else
        Rails.logger.info "[EditorChannel] No active editors found for key: #{@active_key}"
      end
    end

    # Clean up user's recent edits when they disconnect
    cleanup_user_edits(user_id)
  end

  def track_user_edits(user_id, line_numbers)
    return if line_numbers.empty?

    @@mutex.synchronize do
      now = Time.current.to_f
      edit_key = recent_edit_key(user_id)

      @@recent_edits[edit_key] ||= {}

      line_numbers.each { |ln| @@recent_edits[edit_key][ln] = now }

      Rails.logger.info "[EditorChannel] Tracked edits for user #{user_id} on lines: #{line_numbers.inspect}"
      Rails.logger.info "[EditorChannel] User #{user_id} recent edits now: #{@@recent_edits[edit_key].inspect}"

      # Clean up old edits (older than 2 minutes)
      cutoff_time = now - 120 # 2 minutes ago
      @@recent_edits[edit_key].delete_if { |line, timestamp| timestamp < cutoff_time }
    end
  end

  def get_user_recent_edits(user_id)
    @@mutex.synchronize do
      edit_key = recent_edit_key(user_id)
      recent_edits = @@recent_edits[edit_key] || {}

      # Clean up old edits (older than 2 minutes)
      now = Time.current.to_f
      cutoff_time = now - 120 # 2 minutes ago
      recent_edits.delete_if { |line, timestamp| timestamp < cutoff_time }

      recent_edits.dup # Return a copy
    end
  end

  def cleanup_user_edits(user_id)
    @@mutex.synchronize do
      edit_key = recent_edit_key(user_id)
      @@recent_edits.delete(edit_key)
      Rails.logger.info "[EditorChannel] Cleaned up recent edits for user #{user_id}"
    end
  end

  def active_editors_key
    "active_editors_#{@project_id}_#{@branch}_#{@file_id}"
  end

  def recent_edit_key(user_id)
    "recent_edits_user_#{user_id}_file_#{@file_id}_branch_#{@branch}"
  end

  # Class method to inspect current state (useful for debugging)
  def self.debug_state
    Rails.logger.info "[EditorChannel Debug] Active editors: #{@@active_editors.inspect}"
    Rails.logger.info "[EditorChannel Debug] Recent edits: #{@@recent_edits.inspect}"
  end

  # Class method to clean up stale data
  def self.cleanup_stale_data
    @@mutex.synchronize do
      now = Time.current.to_f
      cutoff_time = now - 120 # 2 minutes ago

      @@recent_edits.each do |key, edits|
        edits.delete_if { |line, timestamp| timestamp < cutoff_time }
        @@recent_edits.delete(key) if edits.empty?
      end
    end
  end
end
