class ConflictsController < ApplicationController
  before_action :set_conflict, only: [ :resolve, :ignore ]

  def resolve
    Rails.logger.info "[ConflictsController] Resolving conflict #{@conflict.id}"

    @conflict.update!(resolved: true)

    # Update live content and broadcast to all users
    update_live_content_and_broadcast(@conflict.incoming_content, "accept")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("conflict_#{@conflict.id}"),
          turbo_stream.append("notifications", success_notification_html("✅ Conflict resolved - incoming changes accepted"))
        ]
      end
      format.html do
        redirect_back(fallback_location: root_path, notice: "Conflict resolved")
      end
      format.json do
        render json: {
          status: "resolved",
          content: @conflict.incoming_content,
          conflict_id: @conflict.id,
          message: "Conflict resolved - incoming changes accepted"
        }
      end
    end
  rescue => e
    Rails.logger.error "[ConflictsController] Error resolving conflict: #{e.message}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("notifications", error_notification_html("❌ Error resolving conflict: #{e.message}"))
      end
      format.html do
        redirect_back(fallback_location: root_path, alert: "Error resolving conflict")
      end
      format.json do
        render json: { status: "error", message: e.message }, status: :unprocessable_entity
      end
    end
  end

  def ignore
    Rails.logger.info "[ConflictsController] Ignoring conflict #{@conflict.id}"

    # Get the user's current content (the content they want to keep)
    user_current_content = get_user_current_content(@conflict)

    @conflict.destroy

    # Update live content with user's current content and broadcast
    update_live_content_and_broadcast(user_current_content, "ignore")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("conflict_#{@conflict.id}"),
          turbo_stream.append("notifications", info_notification_html("✅ Conflict ignored - kept your version"))
        ]
      end
      format.html do
        redirect_back(fallback_location: root_path, notice: "Conflict ignored")
      end
      format.json do
        render json: {
          status: "ignored",
          conflict_id: @conflict.id,
          message: "Conflict ignored - kept your version"
        }
      end
    end
  rescue => e
    Rails.logger.error "[ConflictsController] Error ignoring conflict: #{e.message}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("notifications", error_notification_html("❌ Error ignoring conflict: #{e.message}"))
      end
      format.html do
        redirect_back(fallback_location: root_path, alert: "Error ignoring conflict")
      end
      format.json do
        render json: { status: "error", message: e.message }, status: :unprocessable_entity
      end
    end
  end

  def panel
    @conflicts = ConflictQueue.where(
      user_id: current_user.id,
      project_id: params[:project_id],
      file_path: params[:file_id],
      branch: params[:branch],
      resolved: false
    ).order(created_at: :desc)

    Rails.logger.info "[ConflictsController] Loading panel with #{@conflicts.count} conflicts"

    respond_to do |format|
      format.html do
        if @conflicts.any?
          render partial: "conflicts/conflict", collection: @conflicts, as: :conflict
        else
          render html: no_conflicts_html
        end
      end
      format.json do
        render json: {
          status: "success",
          conflicts_count: @conflicts.count,
          html: if @conflicts.any?
                  render_to_string(partial: "conflicts/conflict", collection: @conflicts, as: :conflict)
                else
                  no_conflicts_html
                end
        }
      end
    end
  rescue => e
    Rails.logger.error "[ConflictsController] Error loading panel: #{e.message}"

    respond_to do |format|
      format.html do
        render html: error_alert_html("Error loading conflicts: #{e.message}")
      end
      format.json do
        render json: { status: "error", message: e.message }, status: :internal_server_error
      end
    end
  end

  private

  def set_conflict
    @conflict = ConflictQueue.find(params[:id])

    # Ensure the conflict belongs to the current user for security
    unless @conflict.user_id == current_user.id
      Rails.logger.warn "[ConflictsController] Unauthorized access attempt to conflict #{@conflict.id} by user #{current_user.id}"
      raise ActiveRecord::RecordNotFound
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "[ConflictsController] Conflict not found: #{params[:id]}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("notifications", error_notification_html("❌ Conflict not found"))
      end
      format.html do
        redirect_back(fallback_location: root_path, alert: "Conflict not found")
      end
      format.json do
        render json: { status: "error", message: "Conflict not found" }, status: :not_found
      end
    end
  end

  def update_live_content_and_broadcast(content, action_type)
    stream_key = "editor_#{@conflict.project_id}_#{@conflict.branch}_#{@conflict.file_path}"

    Rails.logger.info "[ConflictsController] Updating live content and broadcasting for #{action_type}"
    Rails.logger.info "[ConflictsController] Stream key: #{stream_key}"

    # Update the live content in EditorChannel
    EditorChannel.update_live_content_for_file(
      @conflict.project_id,
      @conflict.branch,
      @conflict.file_path,
      content
    )

    # Broadcast the updated content to all connected users
    ActionCable.server.broadcast(stream_key, {
      type: "conflict_resolution",
      action: action_type,
      content: content,
      resolved_by: current_user.id,
      conflict_id: @conflict.id,
      timestamp: Time.current.to_f,
      message: action_type == "accept" ? "Conflict resolved - changes accepted" : "Conflict ignored - original content kept"
    })

    Rails.logger.info "[ConflictsController] Broadcasted conflict resolution to #{stream_key}"
  end

  def get_user_current_content(conflict)
    # Try to get the user's current content from EditorChannel
    user_content = EditorChannel.get_user_content_for_conflict(
      conflict.project_id,
      conflict.branch,
      conflict.file_path,
      conflict.user_id
    )

    # Fallback to base_content if user content is not available
    if user_content.blank?
      Rails.logger.info "[ConflictsController] Using base_content as fallback for user #{conflict.user_id}"
      user_content = conflict.base_content
    end

    user_content
  end

  # HTML helper methods
  def success_notification_html(message)
    %(<div class="alert alert-success alert-dismissible fade show" role="alert" data-bs-dismiss="alert">#{message}</div>).html_safe
  end

  def info_notification_html(message)
    %(<div class="alert alert-info alert-dismissible fade show" role="alert" data-bs-dismiss="alert">#{message}</div>).html_safe
  end

  def error_notification_html(message)
    %(<div class="alert alert-danger alert-dismissible fade show" role="alert" data-bs-dismiss="alert">#{message}</div>).html_safe
  end

  def no_conflicts_html
    %(<div class="text-center py-3"><p class="text-muted text-center mb-0">No conflicts</p></div>).html_safe
  end

  def error_alert_html(message)
    %(<div class="alert alert-danger">#{message}</div>).html_safe
  end
end
