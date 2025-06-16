# app/channels/editor_channel.rb
class EditorChannel < ApplicationCable::Channel
  def subscribed
    @project_id = params[:project_id]
    @file_id = params[:file_id]
    @branch = params[:branch]
    @user = current_user
    @room_id = "editor:#{@project_id}:#{@branch}:#{@file_id.gsub('/', ':')}"

    stream_from @room_id

    # Add user to session
    add_user_to_session

    # Get initial content (with fallback to file system)
    initial_content = get_file_content_with_fallback

    # Send initial state
    transmit({
      type: "initial_state",
      content: initial_content,
      users: get_active_users,
      user_id: @user.id
    })

    # Broadcast user joined
    broadcast_to_others({
      type: "user_joined",
      user: user_info(@user)
    })
  end

  def unsubscribed
    remove_user_from_session

    # Broadcast user left
    ActionCable.server.broadcast(@room_id, {
      type: "user_left",
      user_id: @user.id
    })
  end

  def content_update(data)
    Rails.logger.info "Content update from user #{@user.id}: #{data['changes']&.keys}"

    # Store the change with timestamp
    store_user_change(data["changes"])

    # Check for conflicts with more detailed logging
    conflicts = detect_conflicts(data["changes"])
    Rails.logger.info "Detected #{conflicts.length} conflicts for user #{@user.id}"

    if conflicts.any?
      Rails.logger.info "Processing conflicts: #{conflicts}"

      # Store the current content as "pre-conflict" state for other users before updating
      conflicts.each do |conflict|
        store_pre_conflict_content(conflict[:user_id])
      end

      # Create conflict records and notify ONLY the affected users
      conflicts.each do |conflict|
        begin
          # Create conflict record for the OTHER user (not the current user)
          conflict_record = ConflictQueue.create!(
            project_id: @project_id,
            user_id: conflict[:user_id], # This is the OTHER user who will have the conflict
            file_path: @file_id,
            branch: @branch,
            conflicting_lines: conflict[:lines].to_json,
            operation_type: "edit",
            line_start: conflict[:lines].min,
            line_end: conflict[:lines].max
          )
          Rails.logger.info "Created conflict record for user #{conflict[:user_id]} on lines #{conflict[:lines]}"

          # Send conflict notification ONLY to the affected user (not broadcast)
          user_channel = "user_#{conflict[:user_id]}"
          ActionCable.server.broadcast(user_channel, {
            type: "conflict_detected",
            user_id: conflict[:user_id],
            conflicting_user_id: @user.id,
            conflict_id: conflict_record.id,
            lines: conflict[:lines],
            content: data["content"],
            message: "#{user_info(@user)[:name]} edited lines you were working on",
            file_path: @file_id,
            project_id: @project_id
          })
          Rails.logger.info "Sent conflict notification to user #{conflict[:user_id]} via personal channel"

        rescue => e
          Rails.logger.error "Failed to create conflict record: #{e.message}"
        end
      end

      # Notify the current user that their changes caused conflicts
      transmit({
        type: "conflict_created",
        conflicts: conflicts.map { |c| c.merge(lines: c[:lines]) },
        message: "Your changes may conflict with other users' work"
      })
    end

    # Update content in Redis
    update_file_content(data["content"])

    # Broadcast to all except sender
    broadcast_to_others({
      type: "content_update",
      content: data["content"],
      changes: data["changes"],
      user_id: @user.id,
      timestamp: Time.current.to_i
    })
  end

  def cursor_update(data)
    # Update cursor position in Redis
    redis.setex(
      "cursor:#{@room_id}:#{@user.id}",
      60, # 1 minute expiry
      { line: data["line"], column: data["column"], timestamp: Time.current.to_i }.to_json
    )

    # Broadcast to others
    broadcast_to_others({
      type: "cursor_update",
      user_id: @user.id,
      line: data["line"],
      column: data["column"]
    })
  end

  def selection_update(data)
    # Store selection in Redis for conflict detection
    redis.setex(
      "selection:#{@room_id}:#{@user.id}",
      30, # 30 seconds expiry
      {
        start_line: data["start_line"],
        start_column: data["start_column"],
        end_line: data["end_line"],
        end_column: data["end_column"],
        timestamp: Time.current.to_i
      }.to_json
    )

    # Broadcast selection to others
    broadcast_to_others({
      type: "selection_update",
      user_id: @user.id,
      start_line: data["start_line"],
      start_column: data["start_column"],
      end_line: data["end_line"],
      end_column: data["end_column"]
    })
  end

  def request_fresh_state(data)
    # Send fresh content when requested
    fresh_content = get_file_content_with_fallback

    transmit({
      type: "fresh_state",
      content: fresh_content,
      users: get_active_users
    })
  end

  def test_connection(data)
    # Test method for debugging
    Rails.logger.info "Test connection from user #{@user.id}: #{data['message']}"
    transmit({
      type: "test_response",
      message: "Connection working for user #{@user.id}",
      timestamp: Time.current.to_i
    })
  end

  # New method to handle conflict resolution from client
  def resolve_conflict(data)
    conflict_id = data["conflict_id"]
    action = data["resolution_action"] || data["action"]

    Rails.logger.info "Resolving conflict #{conflict_id} with action '#{action}' for user #{@user.id}"
    Rails.logger.info "Received data: #{data.inspect}"

    if action.blank?
      Rails.logger.error "No action provided in resolve_conflict"
      transmit({
        type: "conflict_resolution",
        action: "error",
        message: "No action provided",
        conflict_id: conflict_id
      })
      return
    end

    if conflict_id.blank?
      Rails.logger.error "No conflict_id provided in resolve_conflict"
      transmit({
        type: "conflict_resolution",
        action: "error",
        message: "No conflict ID provided",
        conflict_id: conflict_id
      })
      return
    end

    begin
      conflict = ConflictQueue.find(conflict_id)
      Rails.logger.info "Found conflict: #{conflict.inspect}"

      # Verify the conflict belongs to the current user
      unless conflict.user_id == @user.id
        Rails.logger.warn "User #{@user.id} tried to resolve conflict #{conflict_id} belonging to user #{conflict.user_id}"
        transmit({
          type: "conflict_resolution",
          action: "error",
          message: "You can only resolve your own conflicts",
          conflict_id: conflict_id
        })
        return
      end

      case action
      when "accept"
        # Mark conflict as resolved
        conflict.update!(resolved_at: Time.current) if conflict.respond_to?(:resolve!)
        Rails.logger.info "Marked conflict #{conflict_id} as resolved"

        # Get fresh content and send to user
        fresh_content = get_file_content_with_fallback
        Rails.logger.info "Sending fresh content (#{fresh_content&.length || 0} chars) to user #{@user.id}"

        transmit({
          type: "conflict_resolution",
          action: "accepted",
          content: fresh_content,
          conflict_id: conflict_id
        })

        Rails.logger.info "User #{@user.id} accepted conflict #{conflict_id}"

      when "reject", "ignore"
        # When ignoring, restore content to pre-conflict state
        pre_conflict_content = get_pre_conflict_content(@user.id)

        if pre_conflict_content.present?
          # Update the shared content with pre-conflict version
          update_file_content(pre_conflict_content)
          Rails.logger.info "Restored content to pre-conflict state for user #{@user.id}"

          # Broadcast the pre-conflict content to all users
          broadcast_to_others({
            type: "content_update",
            content: pre_conflict_content,
            user_id: @user.id,
            timestamp: Time.current.to_i,
            conflict_resolution: true
          })

          transmit({
            type: "conflict_resolution",
            action: "ignored",
            content: pre_conflict_content,
            conflict_id: conflict_id,
            message: "Conflict ignored - content restored"
          })

          # Clear the stored pre-conflict content
          clear_pre_conflict_content(@user.id)
        else
          # Fallback: use user_content if provided
          user_content = data["user_content"]
          if user_content.present?
            update_file_content(user_content)
            Rails.logger.info "No pre-conflict content found, using provided user content"

            broadcast_to_others({
              type: "content_update",
              content: user_content,
              user_id: @user.id,
              timestamp: Time.current.to_i,
              conflict_resolution: true
            })

            transmit({
              type: "conflict_resolution",
              action: "ignored",
              content: user_content,
              conflict_id: conflict_id,
              message: "Conflict ignored - your changes preserved"
            })
          else
            Rails.logger.warn "No pre-conflict content or user content available"
            transmit({
              type: "conflict_resolution",
              action: "ignored",
              conflict_id: conflict_id,
              message: "Conflict ignored"
            })
          end
        end

        # Remove the conflict
        conflict.destroy
        Rails.logger.info "Destroyed conflict #{conflict_id}"

      else
        Rails.logger.error "Unknown action '#{action}' for conflict resolution"
        transmit({
          type: "conflict_resolution",
          action: "error",
          message: "Unknown action: #{action}",
          conflict_id: conflict_id
        })
      end

    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn "Conflict #{conflict_id} not found for user #{@user.id}"
      transmit({
        type: "conflict_resolution",
        action: "error",
        message: "Conflict no longer exists",
        conflict_id: conflict_id
      })
    rescue => e
      Rails.logger.error "Error resolving conflict #{conflict_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      transmit({
        type: "conflict_resolution",
        action: "error",
        message: "Failed to resolve conflict: #{e.message}",
        conflict_id: conflict_id
      })
    end
  end

  private

  def add_user_to_session
    redis.multi do |r|
      r.sadd("users:#{@room_id}", @user.id)
      r.setex("user_info:#{@room_id}:#{@user.id}", 300, user_info(@user).to_json)
      r.setex("user_joined:#{@room_id}:#{@user.id}", 300, Time.current.to_i)
    end

    # Also subscribe to personal channel for targeted notifications
    stream_from "user_#{@user.id}"
  end

  def remove_user_from_session
    redis.multi do |r|
      r.srem("users:#{@room_id}", @user.id)
      r.del("user_info:#{@room_id}:#{@user.id}")
      r.del("cursor:#{@room_id}:#{@user.id}")
      r.del("changes:#{@room_id}:#{@user.id}")
      r.del("selection:#{@room_id}:#{@user.id}")
      r.del("user_joined:#{@room_id}:#{@user.id}")
      r.del("pre_conflict:#{@room_id}:#{@user.id}")
    end
  end

  def get_active_users
    user_ids = redis.smembers("users:#{@room_id}")
    users = []

    user_ids.each do |user_id|
      info = redis.get("user_info:#{@room_id}:#{user_id}")
      cursor = redis.get("cursor:#{@room_id}:#{user_id}")

      if info
        user_data = JSON.parse(info)
        user_data["cursor"] = cursor ? JSON.parse(cursor) : nil
        users << user_data
      end
    end

    users
  end

  def get_file_content
    redis.get("content:#{@room_id}")
  end

  def get_file_content_with_fallback
    # Try to get live content from Redis first
    live_content = redis.get("content:#{@room_id}")

    # If no live content exists, fall back to file system
    if live_content.nil?
      file_content = load_file_content_from_disk
      if file_content
        # Store the file content in Redis so other users get the same content
        update_file_content(file_content)
        Rails.logger.info "Loaded file content from disk and stored in Redis for room #{@room_id}"
        return file_content
      else
        Rails.logger.warn "Could not load file content from disk for #{@file_id}"
        return ""
      end
    end

    live_content
  end

  def load_file_content_from_disk
    begin
      project = Project.find(@project_id)
      repo_path = Rails.root.join("storage", "projects", "project_#{project.id}")

      # Parse the file path
      path_parts = @file_id.split("/")
      file_name = path_parts.pop
      directory_path = path_parts.join("/")

      # Construct full path
      full_path = if directory_path.present? && directory_path != "."
                    repo_path.join(directory_path, file_name)
      else
                    repo_path.join(file_name)
      end

      # Check for unsaved version first
      unsaved_path = "#{full_path}.unsaved"
      if File.exist?(unsaved_path)
        Rails.logger.info "Loading unsaved content from #{unsaved_path}"
        return File.read(unsaved_path)
      end

      # Load regular file
      if File.exist?(full_path)
        Rails.logger.info "Loading file content from #{full_path}"
        return File.read(full_path)
      end

      Rails.logger.warn "File not found: #{full_path}"
      nil
    rescue => e
      Rails.logger.error "Error loading file content: #{e.message}"
      nil
    end
  end

  def update_file_content(content)
    redis.setex("content:#{@room_id}", 3600, content) # 1 hour expiry
  end

  def store_pre_conflict_content(user_id)
    # Store the current content as the "pre-conflict" state for a user
    current_content = get_file_content_with_fallback
    pre_conflict_key = "pre_conflict:#{@room_id}:#{user_id}"
    redis.setex(pre_conflict_key, 600, current_content) # 10 minutes expiry
    Rails.logger.info "Stored pre-conflict content for user #{user_id} (#{current_content&.length || 0} chars)"
  end

  def get_pre_conflict_content(user_id)
    # Get the content that existed before the conflict for this user
    pre_conflict_key = "pre_conflict:#{@room_id}:#{user_id}"
    content = redis.get(pre_conflict_key)
    Rails.logger.info "Retrieved pre-conflict content for user #{user_id}: #{content&.length || 0} chars"
    content
  end

  def clear_pre_conflict_content(user_id)
    # Clear the pre-conflict content for a user
    pre_conflict_key = "pre_conflict:#{@room_id}:#{user_id}"
    redis.del(pre_conflict_key)
    Rails.logger.info "Cleared pre-conflict content for user #{user_id}"
  end

  def store_user_change(changes)
    return unless changes

    key = "changes:#{@room_id}:#{@user.id}"
    change_data = {
      changes: changes,
      timestamp: Time.current.to_i,
      user_id: @user.id
    }

    redis.setex(key, 60, change_data.to_json) # 60 seconds expiry
    Rails.logger.info "Stored changes for user #{@user.id}: #{changes}"
  end

  def detect_conflicts(changes)
    conflicts = []
    return conflicts unless changes && changes["lines"]

    current_user_lines = changes["lines"]
    Rails.logger.info "Checking conflicts for lines: #{current_user_lines}"

    # Get other users' recent changes
    user_ids = redis.smembers("users:#{@room_id}").map(&:to_i) - [ @user.id ]
    Rails.logger.info "Checking against users: #{user_ids}"

    user_ids.each do |other_user_id|
      other_changes_raw = redis.get("changes:#{@room_id}:#{other_user_id}")
      next unless other_changes_raw

      begin
        other_change_data = JSON.parse(other_changes_raw)
        other_changes = other_change_data["changes"]
        other_timestamp = other_change_data["timestamp"]

        # Only consider recent changes (within last 60 seconds)
        next if Time.current.to_i - other_timestamp > 60

        Rails.logger.info "Comparing with user #{other_user_id} changes: #{other_changes}"

        # Check for line overlaps
        if other_changes && other_changes["lines"]
          overlapping_lines = current_user_lines & other_changes["lines"]

          if overlapping_lines.any?
            Rails.logger.info "Found overlap on lines #{overlapping_lines} between users #{@user.id} and #{other_user_id}"

            conflicts << {
              user_id: other_user_id,
              lines: overlapping_lines,
              timestamp: other_timestamp
            }
          end
        end

        # Also check selections for potential conflicts
        selection_raw = redis.get("selection:#{@room_id}:#{other_user_id}")
        if selection_raw
          selection_data = JSON.parse(selection_raw)
          selection_lines = (selection_data["start_line"]..selection_data["end_line"]).to_a
          selection_overlap = current_user_lines & selection_lines

          if selection_overlap.any? && Time.current.to_i - selection_data["timestamp"] < 30
            Rails.logger.info "Found selection conflict on lines #{selection_overlap} with user #{other_user_id}"

            conflicts << {
              user_id: other_user_id,
              lines: selection_overlap,
              type: "selection_conflict",
              timestamp: selection_data["timestamp"]
            }
          end
        end
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse change data for user #{other_user_id}: #{e.message}"
      end
    end

    conflicts.uniq { |c| [ c[:user_id], c[:lines] ] }
  end

  def broadcast_to_others(data)
    ActionCable.server.broadcast(@room_id, data.merge(sender_id: @user.id))
  end

  def user_info(user)
    {
      id: user.id,
      name: user.username || user.email,
      color: user_color(user.id)
    }
  end

  def user_color(user_id)
    colors = [ "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57", "#48DBFB", "#FF9FF3", "#54A0FF" ]
    colors[user_id % colors.length]
  end

  def redis
    $redis
  end
end
