class ConflictsController < ApplicationController
  before_action :set_conflict, only: [ :resolve, :ignore ]

  def resolve
    Rails.logger.info "[ConflictsController] Resolving conflict #{@conflict.id}"

    @conflict.update!(resolved: true)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("conflict_#{@conflict.id}")
      end
      format.html do
        render json: {
          status: "resolved",
          content: @conflict.incoming_content,
          conflict_id: @conflict.id
        }
      end
      format.json do
        render json: {
          status: "resolved",
          content: @conflict.incoming_content,
          conflict_id: @conflict.id
        }
      end
    end
  end

  def ignore
    Rails.logger.info "[ConflictsController] Ignoring conflict #{@conflict.id}"

    @conflict.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("conflict_#{@conflict.id}")
      end
      format.html do
        render json: { status: "ignored", conflict_id: @conflict.id }
      end
      format.json do
        render json: { status: "ignored", conflict_id: @conflict.id }
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
        render partial: "conflicts/conflict", collection: @conflicts, as: :conflict
      end
      format.json do
        render json: {
          status: "success",
          conflicts_count: @conflicts.count,
          html: render_to_string(partial: "conflicts/conflict", collection: @conflicts, as: :conflict)
        }
      end
    end
  end

  private

  def set_conflict
    @conflict = ConflictQueue.find(params[:id])
  end
end
