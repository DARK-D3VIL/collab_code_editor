class CreateEditingSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :editing_sessions do |t|
      t.references :project, null: false, foreign_key: true
      t.string :file_path, null: false
      t.string :branch_name, null: false
      t.text :content
      t.integer :revision, default: 0
      t.json :active_users, default: {}
      t.json :pending_conflicts, default: {}
      t.timestamps
    end
    add_index :editing_sessions, [:project_id, :file_path, :branch_name], 
              unique: true, name: 'index_editing_sessions_on_project_file_branch'
    add_index :editing_sessions, :updated_at
  end
end
