class DropDocumentChangesAndEditingSessions < ActiveRecord::Migration[6.1]
  def change
    # Remove foreign keys first (in case they exist)
    remove_foreign_key :document_changes, :projects
    remove_foreign_key :document_changes, :users
    remove_foreign_key :editing_sessions, :projects

    # Drop tables
    drop_table :document_changes do |t|
      # No need to redefine columns unless using `reversible`, so we keep it simple
    end

    drop_table :editing_sessions do |t|
    end
  end
end
