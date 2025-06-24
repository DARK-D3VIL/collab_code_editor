# app/jobs/ai_training_monitor_job.rb
class AiTrainingMonitorJob < ApplicationJob
  queue_as :default
  
  def perform(training_job_id)
    training_job = AiTrainingJob.find(training_job_id)
    project = training_job.project
    
    Rails.logger.info "🔍 Starting monitoring for AI training job #{training_job.job_id}"
    Rails.logger.info "   Initial status: #{training_job.status}"
    Rails.logger.info "   Project status: #{project.ai_training_status}"
    
    max_checks = 240  # 20 minutes with 5-second intervals
    check_count = 0
    
    while check_count < max_checks
      check_count += 1
      
      Rails.logger.info "   Check #{check_count}/#{max_checks} for job #{training_job.job_id}"
      
      # Reload the training job to get latest data
      training_job.reload
      
      # Update status from AI service
      update_success = training_job.update_from_ai_service!
      
      if update_success
        Rails.logger.info "   Current job status: #{training_job.status}, Progress: #{training_job.progress}%"
        
        case training_job.status
        when 'completed'
          Rails.logger.info "   ✅ Training completed successfully!"
          handle_training_completion(training_job, project)
          break
        when 'failed'
          Rails.logger.error "   ❌ Training failed: #{training_job.error_message}"
          handle_training_failure(training_job, project)
          break
        when 'running'
          # Update project status to training if it's still queued
          if project.ai_training_status == 'queued'
            Rails.logger.info "   🔄 Updating project status from queued to training"
            project.update!(ai_training_status: 'training')
          end
        when 'queued'
          Rails.logger.info "   ⏳ Job still queued..."
          # Ensure project status is also queued
          if project.ai_training_status != 'queued'
            Rails.logger.info "   🔄 Updating project status to queued"
            project.update!(ai_training_status: 'queued')
          end
        else
          Rails.logger.warn "   ⚠️ Unknown job status: #{training_job.status}"
        end
      else
        Rails.logger.error "   ❌ Failed to update from AI service on check #{check_count}"
        
        # If we can't reach the service multiple times in a row, something is wrong
        if check_count > 5 && (check_count % 10 == 0)
          Rails.logger.warn "   ⚠️ #{check_count} failed updates - continuing to monitor"
        end
      end
      
      # Break if job is no longer in progress
      unless training_job.in_progress?
        Rails.logger.info "   🔚 Job no longer in progress, stopping monitor"
        break
      end
      
      # Wait before next check
      sleep 5
    end
    
    # Timeout handling
    if check_count >= max_checks && training_job.in_progress?
      Rails.logger.error "   ⏰ Training job #{training_job.job_id} timed out after #{max_checks} checks"
      handle_training_timeout(training_job, project)
    end
    
    Rails.logger.info "🏁 Finished monitoring job #{training_job.job_id}"
    Rails.logger.info "   Final job status: #{training_job.reload.status}"
    Rails.logger.info "   Final project status: #{project.reload.ai_training_status}"
  end
  
  private
  
  def handle_training_completion(training_job, project)
    Rails.logger.info "🎉 Handling training completion for project #{project.id}"
    
    training_job.update!(completed_at: Time.current)
    project.update!(
      ai_training_status: 'completed',
      ai_model_trained_at: Time.current
    )
    
    Rails.logger.info "✅ AI training completed for project #{project.id} (#{project.name})"
    
    # TODO: Add email notification
    # UserMailer.ai_training_completed(training_job.user, project).deliver_later
  end
  
  def handle_training_failure(training_job, project)
    Rails.logger.error "💥 Handling training failure for project #{project.id}"
    Rails.logger.error "   Error: #{training_job.error_message}"
    
    training_job.update!(completed_at: Time.current)
    project.update!(ai_training_status: 'failed')
    
    Rails.logger.error "❌ AI training failed for project #{project.id}: #{training_job.error_message}"
    
    # TODO: Add email notification
    # UserMailer.ai_training_failed(training_job.user, project, training_job.error_message).deliver_later
  end
  
  def handle_training_timeout(training_job, project)
    Rails.logger.error "⏰ Handling training timeout for project #{project.id}"
    
    training_job.update!(
      status: 'failed',
      error_message: 'Training timeout after 20 minutes - monitor stopped checking',
      completed_at: Time.current
    )
    project.update!(ai_training_status: 'failed')
    
    Rails.logger.error "⏰ AI training timeout for project #{project.id} - stopped monitoring after 20 minutes"
  end
end