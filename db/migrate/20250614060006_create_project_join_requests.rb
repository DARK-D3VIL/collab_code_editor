class CreateProjectJoinRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :project_join_requests do |t|
      t.bigint :user_id, null: false
      t.bigint :project_id, null: false
      t.integer :status, default: 0, null: false # enum: pending: 0
      t.timestamps

      t.index [ :user_id ]
      t.index [ :project_id ]
      t.index [ :status ]
      t.index [ :user_id, :project_id ], unique: true # prevent duplicates
    end

    add_foreign_key :project_join_requests, :users
    add_foreign_key :project_join_requests, :projects
  end
end
