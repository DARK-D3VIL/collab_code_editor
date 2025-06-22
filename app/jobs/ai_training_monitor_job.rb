# app/jobs/ai_training_monitor_job.rb
class AiTrainingMonitorJob < ApplicationJob
  queue_as :default
  
  def perform(training_job_id)
    training_job = AiTrainingJob.find(training_job_id)
    project = training_job.project
    
    Rails.logger.info "Monitoring AI training job #{training_job.job_id}"
    
    max_checks = 240  # 20 minutes with 5-second intervals
    check_count = 0
    
    while check_count < max_checks
      check_count += 1
      
      # Update status from AI service
      if training_job.update_from_ai_service!
        case training_job.status
        when 'completed'
          handle_training_completion(training_job, project)
          break
        when 'failed'
          handle_training_failure(training_job, project)
          break
        when 'running'
          project.update!(ai_training_status: 'training') if project.queued?
        end
      end
      
      # Wait before next check
      sleep 5
    end
    
    # Timeout handling
    if check_count >= max_checks && training_job.in_progress?
      handle_training_timeout(training_job, project)
    end
  end
  
  private
  
  def handle_training_completion(training_job, project)
    training_job.update!(completed_at: Time.current)
    project.update!(
      ai_training_status: 'completed',
      ai_model_trained_at: Time.current
    )
    
    Rails.logger.info "AI training completed for project #{project.id}"
    
    # Notify user (you can add email/notification here)
    # UserMailer.ai_training_completed(training_job.user, project).deliver_later
  end
  
  def handle_training_failure(training_job, project)
    training_job.update!(completed_at: Time.current)
    project.update!(ai_training_status: 'failed')
    
    Rails.logger.error "AI training failed for project #{project.id}: #{training_job.error_message}"
    
    # Notify user of failure
    # UserMailer.ai_training_failed(training_job.user, project, training_job.error_message).deliver_later
  end
  
  def handle_training_timeout(training_job, project)
    training_job.update!(
      status: 'failed',
      error_message: 'Training timeout after 20 minutes',
      completed_at: Time.current
    )
    project.update!(ai_training_status: 'failed')
    
    Rails.logger.error "AI training timeout for project #{project.id}"
  end
end