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

ActiveRecord::Schema[8.0].define(version: 2026_01_29_111000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_credentials", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "agent_type", null: false
    t.text "encrypted_config_data", null: false
    t.jsonb "metadata", default: {}
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_type"], name: "index_agent_credentials_on_agent_type"
    t.index ["user_id", "agent_type"], name: "index_agent_credentials_on_user_id_and_agent_type", unique: true
    t.index ["user_id"], name: "index_agent_credentials_on_user_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "state", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "display_name"
    t.string "logo_url"
    t.string "primary_color", default: "#4785FF"
    t.string "secondary_color", default: "#bb9af7"
    t.string "email_domain", null: false
    t.boolean "auto_accept_users", default: false, null: false
    t.text "logo_data"
    t.index ["email_domain"], name: "index_companies_on_email_domain", unique: true
    t.index ["name"], name: "index_companies_on_name", unique: true
    t.index ["slug"], name: "index_companies_on_slug", unique: true
    t.index ["state"], name: "index_companies_on_state"
  end

  create_table "project_collaborators", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "user_id"], name: "index_project_collaborators_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_collaborators_on_project_id"
    t.index ["user_id"], name: "index_project_collaborators_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "slug", null: false
    t.string "state", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "owner_id", null: false
    t.string "preferred_artifacts_language", default: "en"
    t.index ["company_id", "name"], name: "index_projects_on_company_id_and_name", unique: true
    t.index ["company_id", "slug"], name: "index_projects_on_company_id_and_slug", unique: true
    t.index ["company_id"], name: "index_projects_on_company_id"
    t.index ["owner_id"], name: "index_projects_on_owner_id"
    t.index ["state"], name: "index_projects_on_state"
  end

  create_table "terminal_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id"
    t.string "session_type", null: false
    t.string "agent_type"
    t.string "state", null: false
    t.string "temporal_workflow_id"
    t.string "temporal_run_id"
    t.string "container_id"
    t.string "artifacts_path"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "collected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "route_token"
    t.index ["project_id"], name: "index_terminal_sessions_on_project_id"
    t.index ["route_token"], name: "index_terminal_sessions_on_route_token", unique: true
    t.index ["session_type"], name: "index_terminal_sessions_on_session_type"
    t.index ["state"], name: "index_terminal_sessions_on_state"
    t.index ["temporal_workflow_id"], name: "index_terminal_sessions_on_temporal_workflow_id"
    t.index ["user_id", "session_type"], name: "index_terminal_sessions_on_user_id_and_session_type"
    t.index ["user_id", "state"], name: "index_terminal_sessions_on_user_id_and_state"
    t.index ["user_id"], name: "index_terminal_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "company_id"
    t.citext "email", null: false
    t.string "name", null: false
    t.string "password_digest"
    t.string "state", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "position"
    t.string "preferred_agent_language", default: "en"
    t.string "provider"
    t.string "uid"
    t.string "google_token"
    t.string "google_refresh_token"
    t.string "avatar_url"
    t.text "selected_agents", default: [], array: true
    t.string "onboarding_state", default: "step1", null: false
    t.datetime "onboarding_completed_at"
    t.index ["company_id", "email"], name: "index_users_on_company_id_and_email", unique: true, where: "(company_id IS NOT NULL)"
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["onboarding_state"], name: "index_users_on_onboarding_state"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["state"], name: "index_users_on_state"
  end

  add_foreign_key "agent_credentials", "users"
  add_foreign_key "project_collaborators", "projects"
  add_foreign_key "project_collaborators", "users"
  add_foreign_key "projects", "companies"
  add_foreign_key "projects", "users", column: "owner_id"
  add_foreign_key "terminal_sessions", "projects"
  add_foreign_key "terminal_sessions", "users"
  add_foreign_key "users", "companies"
end
