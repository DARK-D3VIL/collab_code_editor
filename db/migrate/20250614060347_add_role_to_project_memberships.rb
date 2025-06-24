class AddRoleToProjectMemberships < ActiveRecord::Migration[7.2]
  def change
    add_column :project_memberships, :role, :integer, default: 0, null: false
    # enum: reader: 0, writer: 1

    add_index :project_memberships, [ :project_id, :role ]
  end
end
