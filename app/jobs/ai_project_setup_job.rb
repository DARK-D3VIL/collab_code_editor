# app/jobs/ai_project_setup_job.rb
class AiProjectSetupJob < ApplicationJob
  queue_as :default
  
  def perform(project_id, user_id)
    project = Project.find(project_id)
    user = User.find(user_id)
    
    Rails.logger.info "Setting up AI training for project #{project_id}"
    
    # Wait a bit to ensure project directory is created
    sleep 2
    
    # Check if project directory exists (wait up to 10 seconds)
    10.times do
      repo_path = project.repository_path
      
      if Dir.exist?(repo_path)
        Rails.logger.info "Project directory ready, starting AI training"
        training_job = project.start_ai_training!(user)
        
        if training_job
          Rails.logger.info "AI training started successfully: #{training_job.job_id}"
          
          # Start monitoring the training job
          AiTrainingMonitorJob.perform_later(training_job.id)
        else
          Rails.logger.error "Failed to start AI training for project #{project_id}"
        end
        
        break
      end
      
      Rails.logger.info "Waiting for project directory to be created..."
      sleep 1
    end
  end
end