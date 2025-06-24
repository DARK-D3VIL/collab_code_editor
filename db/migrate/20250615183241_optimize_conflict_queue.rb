class OptimizeConflictQueue < ActiveRecord::Migration[7.0]
  def change
    # Remove the heavy text columns
    remove_column :conflict_queues, :content, :text
    remove_column :conflict_queues, :base_content, :text
    remove_column :conflict_queues, :incoming_content, :text
    remove_column :conflict_queues, :changed_lines, :json

    # Add lightweight columns
    add_column :conflict_queues, :operation_type, :string, null: false
    add_column :conflict_queues, :line_start, :integer, null: false
    add_column :conflict_queues, :line_end, :integer, null: false
    add_column :conflict_queues, :resolved_at, :datetime

    # Rename lines_changed to conflicting_lines for clarity
    rename_column :conflict_queues, :lines_changed, :conflicting_lines

    # Add indexes for performance
    add_index :conflict_queues, [ :project_id, :file_path, :branch, :resolved ],
              name: 'index_conflicts_on_file_and_resolved'
    add_index :conflict_queues, [ :line_start, :line_end ],
              name: 'index_conflicts_on_line_range'
    add_index :conflict_queues, :created_at
  end
end
