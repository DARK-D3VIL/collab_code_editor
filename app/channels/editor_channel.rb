class EditorChannel < ApplicationCable::Channel
  def subscribed
    project_id = params[:project_id]
    file_id = params[:file_id]
    branch = params[:branch]

    stream_from "editor_#{project_id}_#{branch}_#{file_id}"
  end

  def receive(data)
    project_id = params[:project_id]
    file_id = params[:file_id]
    branch = params[:branch]

    ActionCable.server.broadcast("editor_#{project_id}_#{branch}_#{file_id}", data)
  end
end
