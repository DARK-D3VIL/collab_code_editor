class AddAiTrainingToProjects < ActiveRecord::Migration[7.0]
  def change
    add_column :projects, :ai_training_status, :string, default: 'not_started'
    add_column :projects, :ai_model_trained_at, :datetime
    add_column :projects, :ai_training_enabled, :boolean, default: true
    
    add_index :projects, :ai_training_status
  end
end