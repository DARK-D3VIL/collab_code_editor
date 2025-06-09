class CreateProjects < ActiveRecord::Migration[7.2]
  def change
    create_table :projects do |t|
      t.string :name
      t.string :slug
      t.integer :owner_id

      t.timestamps
    end
  end
end
