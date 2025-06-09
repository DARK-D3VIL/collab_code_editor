class CreateProjectFiles < ActiveRecord::Migration[6.1]
  def change
    create_table :project_files do |t|
      t.references :project, null: false, foreign_key: true
      t.string :path, null: false
      t.string :name, null: false
      t.string :language, null: false

      t.timestamps
    end
  end
end
