class CreateProjectMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :project_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.integer :current_branch_id

      t.timestamps
    end
  end
end
