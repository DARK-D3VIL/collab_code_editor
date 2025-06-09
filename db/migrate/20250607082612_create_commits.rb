class CreateCommits < ActiveRecord::Migration[6.1]
  def change
    create_table :commits do |t|
      t.references :user, null: false, foreign_key: true         # Author of the commit
      t.references :branch, null: false, foreign_key: true       # Branch where commit belongs
      t.references :project, null: false, foreign_key: true      # Project where commit belongs

      t.string :message                                           # Commit message
      t.string :sha, null: false                                  # Git SHA (unique identifier)
      t.string :parent_sha                                        # Parent SHA (nil for first commit)

      t.timestamps                                                # Includes created_at as commit time
    end

    add_index :commits, :sha, unique: true
  end
end
