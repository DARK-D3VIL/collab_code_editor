# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_06_12_094312) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "branches", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.integer "created_by", null: false
    t.integer "file_ids", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_branches_on_project_id"
  end

  create_table "commits", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "branch_id", null: false
    t.bigint "project_id", null: false
    t.string "message"
    t.string "sha", null: false
    t.string "parent_sha"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_commits_on_branch_id"
    t.index ["project_id"], name: "index_commits_on_project_id"
    t.index ["sha"], name: "index_commits_on_sha", unique: true
    t.index ["user_id"], name: "index_commits_on_user_id"
  end

  create_table "conflict_queues", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.string "file_path", null: false
    t.string "branch", null: false
    t.text "content"
    t.text "base_content"
    t.text "incoming_content"
    t.json "lines_changed"
    t.json "changed_lines"
    t.boolean "resolved", default: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["project_id", "file_path", "branch"], name: "index_conflict_queues_on_project_id_and_file_path_and_branch"
    t.index ["project_id"], name: "index_conflict_queues_on_project_id"
    t.index ["user_id", "resolved"], name: "index_conflict_queues_on_user_id_and_resolved"
    t.index ["user_id"], name: "index_conflict_queues_on_user_id"
  end

  create_table "project_files", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "path", null: false
    t.string "name", null: false
    t.string "language", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_project_files_on_project_id"
  end

  create_table "project_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id", null: false
    t.integer "current_branch_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.integer "owner_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.string "github_token"
    t.string "provider"
    t.string "uid"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "branches", "projects"
  add_foreign_key "commits", "branches"
  add_foreign_key "commits", "projects"
  add_foreign_key "commits", "users"
  add_foreign_key "conflict_queues", "projects"
  add_foreign_key "conflict_queues", "users"
  add_foreign_key "project_files", "projects"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
end
