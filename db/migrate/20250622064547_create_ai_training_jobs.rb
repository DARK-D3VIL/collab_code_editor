# db/migrate/add_ai_training_jobs.rb
class CreateAiTrainingJobs < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_training_jobs do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :job_id, null: false, index: { unique: true }
      t.string :status, null: false, default: 'queued'
      t.integer :progress, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      
      t.timestamps
    end
    
    add_index :ai_training_jobs, [:project_id, :created_at]
    add_index :ai_training_jobs, :status
  end
end