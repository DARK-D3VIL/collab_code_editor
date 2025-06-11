class CreateDocumentChanges < ActiveRecord::Migration[7.0]
  def change
    create_table :document_changes do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :file_path, null: false
      t.string :branch_name, null: false
      t.integer :start_line
      t.integer :end_line
      t.integer :start_column
      t.integer :end_column
      t.text :content
      t.string :operation_type, null: false
      t.integer :revision
      t.json :operation_data
      t.timestamps
    end

    add_index :document_changes, [:project_id, :file_path, :branch_name], 
              name: 'idx_doc_changes_project_file_branch'
    add_index :document_changes, :revision
    add_index :document_changes, :created_at
  end
end