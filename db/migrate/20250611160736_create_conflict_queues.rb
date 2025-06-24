class CreateConflictQueues < ActiveRecord::Migration[7.0]
  def change
    create_table :conflict_queues do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :file_path, null: false
      t.string :branch, null: false
      t.text :content # The full incoming content
      t.text :base_content # The base content before changes
      t.text :incoming_content # Same as content, for clarity
      t.json :lines_changed # Array of line numbers that conflict
      t.json :changed_lines # Hash with line number => { incoming: "...", existing: "..." }
      t.boolean :resolved, default: false
      t.timestamp :created_at
      t.timestamp :updated_at
    end

    add_index :conflict_queues, [:user_id, :resolved]
    add_index :conflict_queues, [:project_id, :file_path, :branch]
  end
end