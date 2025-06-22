# app/models/ai_training_job.rb
class AiTrainingJob < ApplicationRecord
  belongs_to :project
  belongs_to :user
  
  validates :job_id, presence: true, uniqueness: true
  validates :status, presence: true
  
  enum status: {
    queued: 'queued',
    running: 'running', 
    completed: 'completed',
    failed: 'failed'
  }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }
  
  def completed_successfully?
    status == 'completed'
  end
  
  def in_progress?
    %w[queued running].include?(status)
  end
  
  def update_from_ai_service!
    ai_status = AiCompletionService.check_training_status(job_id)
    return false unless ai_status
    
    update!(
      status: ai_status['status'],
      progress: ai_status['progress'] || 0,
      error_message: ai_status['error_message']
    )
    
    true
  rescue StandardError => e
    Rails.logger.error "Failed to update training job #{job_id}: #{e.message}"
    false
  end
end