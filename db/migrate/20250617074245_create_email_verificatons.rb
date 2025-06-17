class CreateEmailVerificatons < ActiveRecord::Migration[7.2]
  def change
    create_table :email_verifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :email, null: false
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    # Add indexes for performance
    add_index :email_verifications, :token, unique: true
    add_index :email_verifications, :expires_at
    add_index :email_verifications, [ :user_id, :email ]

    # Add email_verified_at to users table
    add_column :users, :email_verified_at, :datetime
    add_index :users, :email_verified_at
  end
end
