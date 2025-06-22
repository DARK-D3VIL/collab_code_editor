class Project < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships

  # Add the new association for join requests
  has_many :project_join_requests, dependent: :destroy
  has_many :pending_requests, -> { pending }, class_name: "ProjectJoinRequest"

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  has_many :branches, dependent: :destroy
  has_many :files, class_name: "ProjectFile", dependent: :destroy
  has_many :conflict_queues, dependent: :destroy

  # Add permission checking method
  def can_user_access?(user, permission = :read)
    return true if owner_id == user.id # Owner has all permissions

    membership = project_memberships.find_by(user: user, active: true)
    return false unless membership

    case permission
    when :read then true # All active members can read
    when :write then membership.writer?
    when :manage then false # Only owner can manage (handled above)
    else false
    end
  end

  # Helper method to check for pending requests
  def has_pending_request?(user)
    project_join_requests.pending.exists?(user: user)
  end
  has_many :ai_training_jobs, dependent: :destroy
  
  enum ai_training_status: {
    not_started: 'not_started',
    queued: 'queued', 
    training: 'training',
    completed: 'completed',
    failed: 'failed'
  }
  
  def latest_training_job
    ai_training_jobs.recent.first
  end
  
  def ai_model_available?
    ai_training_status == 'completed' && ai_model_trained_at.present?
  end
  
  def can_start_ai_training?
    ai_training_enabled? && !training_in_progress?
  end
  
  def training_in_progress?
    %w[queued training].include?(ai_training_status)
  end
  
  def start_ai_training!(user, force_retrain: false)
    return false unless can_start_ai_training? || force_retrain
    
    # Check if AI service is available
    unless AiCompletionService.health_check
      Rails.logger.error "AI service is not available for project #{id}"
      return false
    end
    
    repository_path = Rails.root.join("storage", "projects", "project_#{id}").to_s
    
    # Start training via AI service
    job_data = AiCompletionService.start_training(id, repository_path, force_retrain: force_retrain)
    
    if job_data
      # Create local tracking record
      training_job = ai_training_jobs.create!(
        user: user,
        job_id: job_data['job_id'],
        status: job_data['status'] || 'queued',
        started_at: Time.current
      )
      
      # Update project status
      update!(
        ai_training_status: 'queued',
        ai_model_trained_at: nil
      )
      
      # Start background job to monitor progress
      AiTrainingMonitorJob.perform_later(training_job.id)
      
      Rails.logger.info "AI training started for project #{id}: #{job_data['job_id']}"
      training_job
    else
      Rails.logger.error "Failed to start AI training for project #{id}"
      nil
    end
  end
  
  def repository_path
    Rails.root.join("storage", "projects", "project_#{id}").to_s
  end
end
