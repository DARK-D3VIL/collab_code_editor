class EditorChannel < ApplicationCable::Channel
  def subscribed
    @project_id = params[:project_id]
    @file_path = params[:file_path]
    @branch_name = params[:branch_name]

    if @project_id.blank? || @file_path.blank? || @branch_name.blank?
      reject
      return
    end

    stream_key = stream_name(@project_id, @file_path, @branch_name)
    stream_from stream_key

    @session = EditingSession.find_or_initialize_for_file(@project_id, @file_path, @branch_name)
    @session.revision ||= 1
    @session.save!

    @session.add_user(current_user.id, { name: current_user.name || "User#{current_user.id}" })
  end

  def receive(data)
    type = data["type"]
    payload = data["payload"]

    return unless type == "edit"
    return unless payload

    incoming_revision = payload["revision"].to_i
    content = payload["content"]

    unless @session
      logger.error "EditingSession not initialized"
      return
    end

    if incoming_revision == @session.revision
      @session.increment_revision!
      @session.touch # updates updated_at to avoid cleanup

      ActionCable.server.broadcast(stream_name(@project_id, @file_path, @branch_name), {
        type: "change",
        payload: payload
      })
    else
      @session.add_conflict_for_user(current_user.id, {
        id: SecureRandom.uuid,
        submitted_revision: incoming_revision,
        current_revision: @session.revision,
        content: content
      })

      transmit(type: "conflict", current_revision: @session.revision)
    end
  end

  def unsubscribed
    if @session
      @session.remove_user(current_user.id)
    end
  end

  private

  def stream_name(project_id, file_path, branch_name)
    "editor:#{project_id}:#{branch_name}:#{file_path}"
  end
end
