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

ActiveRecord::Schema[8.0].define(version: 2026_02_04_170001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "action_mcp_session_messages", force: :cascade do |t|
    t.string "session_id", null: false
    t.string "direction", default: "client", null: false, comment: "The message recipient"
    t.string "message_type", null: false, comment: "The type of the message"
    t.string "jsonrpc_id"
    t.json "message_json"
    t.boolean "is_ping", default: false, null: false, comment: "Whether the message is a ping"
    t.boolean "request_acknowledged", default: false, null: false
    t.boolean "request_cancelled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_action_mcp_session_messages_on_session_id"
  end

  create_table "action_mcp_session_resources", force: :cascade do |t|
    t.string "session_id", null: false
    t.string "uri", null: false
    t.string "name"
    t.text "description"
    t.string "mime_type", null: false
    t.boolean "created_by_tool", default: false
    t.datetime "last_accessed_at"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_action_mcp_session_resources_on_session_id"
  end

  create_table "action_mcp_session_subscriptions", force: :cascade do |t|
    t.string "session_id", null: false
    t.string "uri", null: false
    t.datetime "last_notification_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_action_mcp_session_subscriptions_on_session_id"
  end

  create_table "action_mcp_sessions", id: :string, force: :cascade do |t|
    t.string "role", default: "server", null: false, comment: "The role of the session"
    t.string "status", default: "pre_initialize", null: false
    t.datetime "ended_at", comment: "The time the session ended"
    t.string "protocol_version"
    t.json "server_capabilities", comment: "The capabilities of the server"
    t.json "client_capabilities", comment: "The capabilities of the client"
    t.json "server_info", comment: "The information about the server"
    t.json "client_info", comment: "The information about the client"
    t.boolean "initialized", default: false, null: false
    t.integer "messages_count", default: 0, null: false
    t.integer "sse_event_counter", default: 0, null: false
    t.json "tool_registry", default: []
    t.json "prompt_registry", default: []
    t.json "resource_registry", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "consents", default: {}, null: false
  end

  create_table "action_mcp_sse_events", force: :cascade do |t|
    t.string "session_id", null: false
    t.integer "event_id", null: false
    t.text "data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_action_mcp_sse_events_on_created_at"
    t.index ["session_id", "event_id"], name: "index_action_mcp_sse_events_on_session_id_and_event_id", unique: true
    t.index ["session_id"], name: "index_action_mcp_sse_events_on_session_id"
  end

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

  create_table "agents", force: :cascade do |t|
    t.string "name", null: false
    t.string "title", null: false
    t.string "icon"
    t.text "persona", null: false
    t.text "communication_style"
    t.text "principles"
    t.string "source", default: "custom", null: false
    t.string "scope_type", null: false
    t.bigint "scope_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scope_type", "scope_id", "name"], name: "index_agents_on_scope_type_and_scope_id_and_name", unique: true
    t.index ["scope_type", "scope_id"], name: "index_agents_on_scope_type_and_scope_id"
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

  create_table "config_items", force: :cascade do |t|
    t.string "name", null: false
    t.text "value"
    t.text "encrypted_value"
    t.text "description"
    t.string "item_type", null: false
    t.string "scope_type", null: false
    t.bigint "scope_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scope_type", "scope_id", "name"], name: "index_config_items_on_scope_type_and_scope_id_and_name", unique: true
    t.index ["scope_type", "scope_id"], name: "index_config_items_on_scope_type_and_scope_id"
  end

  create_table "mcp_servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "display_name", null: false
    t.string "url"
    t.string "transport", default: "sse"
    t.jsonb "headers", default: {}
    t.text "description"
    t.string "kind", default: "custom", null: false
    t.string "scope_type"
    t.bigint "scope_id"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "scope_type", "scope_id"], name: "index_mcp_servers_on_name_and_scope_type_and_scope_id", unique: true
    t.index ["scope_type", "scope_id"], name: "index_mcp_servers_on_scope"
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

  create_table "session_tools", force: :cascade do |t|
    t.bigint "terminal_session_id", null: false
    t.bigint "tool_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["terminal_session_id", "tool_id"], name: "index_session_tools_on_terminal_session_id_and_tool_id", unique: true
    t.index ["terminal_session_id"], name: "index_session_tools_on_terminal_session_id"
    t.index ["tool_id"], name: "index_session_tools_on_tool_id"
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
    t.string "mcp_key"
    t.index ["mcp_key"], name: "index_terminal_sessions_on_mcp_key", unique: true
    t.index ["project_id"], name: "index_terminal_sessions_on_project_id"
    t.index ["route_token"], name: "index_terminal_sessions_on_route_token", unique: true
    t.index ["session_type"], name: "index_terminal_sessions_on_session_type"
    t.index ["state"], name: "index_terminal_sessions_on_state"
    t.index ["temporal_workflow_id"], name: "index_terminal_sessions_on_temporal_workflow_id"
    t.index ["user_id", "session_type"], name: "index_terminal_sessions_on_user_id_and_session_type"
    t.index ["user_id", "state"], name: "index_terminal_sessions_on_user_id_and_state"
    t.index ["user_id"], name: "index_terminal_sessions_on_user_id"
  end

  create_table "tool_files", force: :cascade do |t|
    t.bigint "tool_id", null: false
    t.string "path", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tool_id", "path"], name: "index_tool_files_on_tool_id_and_path", unique: true
    t.index ["tool_id"], name: "index_tool_files_on_tool_id"
  end

  create_table "tools", force: :cascade do |t|
    t.string "name", null: false
    t.string "display_name", null: false
    t.text "description"
    t.string "scope_type"
    t.bigint "scope_id"
    t.string "docker_image"
    t.text "command"
    t.jsonb "required_config_items", default: []
    t.jsonb "input_schema", default: {}
    t.boolean "enabled", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kind", default: "custom", null: false
    t.index ["kind"], name: "index_tools_on_kind"
    t.index ["scope_type", "scope_id", "name"], name: "index_tools_on_scope_type_and_scope_id_and_name", unique: true
    t.index ["scope_type"], name: "index_tools_on_scope_type"
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
    t.bigint "invited_by_id"
    t.datetime "invited_at"
    t.index ["company_id", "email"], name: "index_users_on_company_id_and_email", unique: true, where: "(company_id IS NOT NULL)"
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["onboarding_state"], name: "index_users_on_onboarding_state"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["state"], name: "index_users_on_state"
  end

  add_foreign_key "action_mcp_session_messages", "action_mcp_sessions", column: "session_id", name: "fk_action_mcp_session_messages_session_id", on_update: :cascade, on_delete: :cascade
  add_foreign_key "action_mcp_session_resources", "action_mcp_sessions", column: "session_id", on_delete: :cascade
  add_foreign_key "action_mcp_session_subscriptions", "action_mcp_sessions", column: "session_id", on_delete: :cascade
  add_foreign_key "action_mcp_sse_events", "action_mcp_sessions", column: "session_id"
  add_foreign_key "agent_credentials", "users"
  add_foreign_key "project_collaborators", "projects"
  add_foreign_key "project_collaborators", "users"
  add_foreign_key "projects", "companies"
  add_foreign_key "projects", "users", column: "owner_id"
  add_foreign_key "session_tools", "terminal_sessions"
  add_foreign_key "session_tools", "tools"
  add_foreign_key "terminal_sessions", "projects"
  add_foreign_key "terminal_sessions", "users"
  add_foreign_key "tool_files", "tools"
  add_foreign_key "users", "companies"
  add_foreign_key "users", "users", column: "invited_by_id"
end
