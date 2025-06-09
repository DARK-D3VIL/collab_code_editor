class CreateBranches < ActiveRecord::Migration[6.1]
  def change
    create_table :branches do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :created_by, null: false
      t.integer :file_ids, array: true, default: []

      t.timestamps
    end
  end
end
