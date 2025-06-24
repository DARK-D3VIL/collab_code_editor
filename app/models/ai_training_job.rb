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
    Rails.logger.info "🔄 Updating training job #{job_id} from AI service"
    
    ai_status = AiCompletionService.check_training_status(job_id)
    return false unless ai_status
    
    Rails.logger.info "   AI Service Status: #{ai_status.inspect}"
    
    # Extract status information
    new_status = ai_status['status']
    new_progress = ai_status['progress'] || 0
    new_error = ai_status['error_message']
    
    # Map microservice status to Rails status
    mapped_status = case new_status
                   when 'running'
                     'running'  # Keep as running, project will use 'training'
                   when 'queued'
                     'queued'
                   when 'completed'
                     'completed'
                   when 'failed'
                     'failed'
                   else
                     Rails.logger.warn "   ⚠️ Unknown status from AI service: #{new_status}"
                     new_status
                   end
    
    Rails.logger.info "   Updating status from '#{status}' to '#{mapped_status}'"
    Rails.logger.info "   Progress: #{progress} -> #{new_progress}"
    
    # Update the record
    update!(
      status: mapped_status,
      progress: new_progress,
      error_message: new_error
    )
    
    Rails.logger.info "   ✅ Successfully updated training job status"
    
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "❌ Failed to update training job #{job_id} - Validation error: #{e.message}"
    Rails.logger.error "   Attempted status: #{ai_status['status']} -> #{mapped_status}"
    Rails.logger.error "   Valid statuses: #{self.class.statuses.keys}"
    false
  rescue StandardError => e
    Rails.logger.error "❌ Failed to update training job #{job_id}: #{e.message}"
    Rails.logger.error "   Backtrace: #{e.backtrace.first(5).join('\n   ')}"
    false
  end
end