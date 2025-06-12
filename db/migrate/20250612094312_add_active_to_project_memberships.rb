class AddActiveToProjectMemberships < ActiveRecord::Migration[7.0]
  def change
    add_column :project_memberships, :active, :boolean, default: true, null: false
  end
end
