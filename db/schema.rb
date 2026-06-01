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

ActiveRecord::Schema[8.1].define(version: 2026_06_01_053713) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "action_mcp_session_messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "direction", default: "client", null: false, comment: "The message recipient"
    t.boolean "is_ping", default: false, null: false, comment: "Whether the message is a ping"
    t.string "jsonrpc_id"
    t.json "message_json"
    t.string "message_type", null: false, comment: "The type of the message"
    t.boolean "request_acknowledged", default: false, null: false
    t.boolean "request_cancelled", default: false, null: false
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_action_mcp_session_messages_on_session_id"
  end

  create_table "action_mcp_session_resources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "created_by_tool", default: false
    t.text "description"
    t.datetime "last_accessed_at"
    t.json "metadata"
    t.string "mime_type", null: false
    t.string "name"
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.string "uri", null: false
    t.index ["session_id"], name: "index_action_mcp_session_resources_on_session_id"
  end

  create_table "action_mcp_session_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_notification_at"
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.string "uri", null: false
    t.index ["session_id"], name: "index_action_mcp_session_subscriptions_on_session_id"
  end

  create_table "action_mcp_session_tasks", id: :string, force: :cascade do |t|
    t.json "continuation_state", default: {}
    t.datetime "created_at", null: false
    t.datetime "last_step_at"
    t.datetime "last_updated_at", null: false
    t.integer "poll_interval", comment: "Suggested polling interval in milliseconds"
    t.string "progress_message"
    t.integer "progress_percent"
    t.string "request_method", comment: "e.g., tools/call, prompts/get"
    t.string "request_name", comment: "e.g., tool name, prompt name"
    t.json "request_params", comment: "Original request params"
    t.json "result_payload", comment: "Final result data"
    t.string "session_id", null: false
    t.string "status", default: "working", null: false
    t.string "status_message"
    t.integer "ttl", comment: "Time to live in milliseconds"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_action_mcp_session_tasks_on_created_at"
    t.index ["session_id", "status"], name: "index_action_mcp_session_tasks_on_session_id_and_status"
    t.index ["session_id"], name: "index_action_mcp_session_tasks_on_session_id"
    t.index ["status"], name: "index_action_mcp_session_tasks_on_status"
  end

  create_table "action_mcp_sessions", id: :string, force: :cascade do |t|
    t.json "client_capabilities", comment: "The capabilities of the client"
    t.json "client_info", comment: "The information about the client"
    t.json "consents", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at", comment: "The time the session ended"
    t.boolean "initialized", default: false, null: false
    t.integer "messages_count", default: 0, null: false
    t.json "prompt_registry", default: []
    t.string "protocol_version"
    t.json "resource_registry", default: []
    t.string "role", default: "server", null: false, comment: "The role of the session"
    t.json "server_capabilities", comment: "The capabilities of the server"
    t.json "server_info", comment: "The information about the server"
    t.string "status", default: "pre_initialize", null: false
    t.json "tool_registry", default: []
    t.datetime "updated_at", null: false
  end

  create_table "action_mcp_sse_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "data", null: false
    t.integer "event_id", null: false
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_action_mcp_sse_events_on_created_at"
    t.index ["session_id", "event_id"], name: "index_action_mcp_sse_events_on_session_id_and_event_id", unique: true
    t.index ["session_id"], name: "index_action_mcp_sse_events_on_session_id"
  end

  create_table "agent_credentials", force: :cascade do |t|
    t.string "agent_type", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_config_data", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["agent_type"], name: "index_agent_credentials_on_agent_type"
    t.index ["user_id", "agent_type"], name: "index_agent_credentials_on_user_id_and_agent_type", unique: true
    t.index ["user_id"], name: "index_agent_credentials_on_user_id"
  end

  create_table "agents", force: :cascade do |t|
    t.text "communication_style"
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name", null: false
    t.text "persona", null: false
    t.text "principles"
    t.bigint "scope_id", null: false
    t.string "scope_type", null: false
    t.string "source", default: "custom", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["scope_type", "scope_id", "name"], name: "index_agents_on_scope_type_and_scope_id_and_name", unique: true
    t.index ["scope_type", "scope_id"], name: "index_agents_on_scope_type_and_scope_id"
  end

  create_table "asset_versions", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "file_data"
    t.bigint "file_size"
    t.string "source", default: "upload", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id", null: false
    t.integer "version", default: 1, null: false
    t.index ["asset_id", "version"], name: "index_asset_versions_on_asset_id_and_version", unique: true
    t.index ["asset_id"], name: "index_asset_versions_on_asset_id"
  end

  create_table "assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.datetime "deleted_at"
    t.string "folder"
    t.string "name", null: false
    t.boolean "public", default: false
    t.string "public_token"
    t.datetime "reviewed_at"
    t.bigint "scope_id", null: false
    t.string "scope_type", null: false
    t.string "status", default: "active", null: false
    t.bigint "step_run_id"
    t.string "tags", default: [], array: true
    t.bigint "terminal_session_id"
    t.datetime "updated_at", null: false
    t.index "scope_type, scope_id, COALESCE(folder, ''::character varying), name", name: "index_assets_on_scope_folder_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["created_by_id"], name: "index_assets_on_created_by_id"
    t.index ["deleted_at"], name: "index_assets_on_deleted_at"
    t.index ["scope_type", "scope_id"], name: "index_assets_on_scope_type_and_scope_id"
    t.index ["status"], name: "index_assets_on_status"
    t.index ["step_run_id"], name: "index_assets_on_step_run_id", where: "(step_run_id IS NOT NULL)"
    t.index ["terminal_session_id"], name: "index_assets_on_terminal_session_id"
  end

  create_table "board_activities", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "actor_type", null: false
    t.bigint "board_id", null: false
    t.bigint "board_task_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.index ["actor_id"], name: "index_board_activities_on_actor_id"
    t.index ["board_id", "created_at"], name: "index_board_activities_on_board_id_and_created_at"
    t.index ["board_id"], name: "index_board_activities_on_board_id"
    t.index ["board_task_id", "created_at"], name: "index_board_activities_on_board_task_id_and_created_at"
    t.index ["board_task_id"], name: "index_board_activities_on_board_task_id"
    t.index ["event_type"], name: "index_board_activities_on_event_type"
  end

  create_table "board_columns", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.text "purpose"
    t.datetime "updated_at", null: false
    t.index ["board_id", "position"], name: "index_board_columns_on_board_id_and_position", unique: true
    t.index ["board_id"], name: "index_board_columns_on_board_id"
  end

  create_table "board_tasks", force: :cascade do |t|
    t.bigint "assignee_id"
    t.bigint "board_column_id", null: false
    t.bigint "board_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "parent_task_id"
    t.integer "position", null: false
    t.string "priority"
    t.string "tags", default: [], array: true
    t.string "task_type", default: "not_specified", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_board_tasks_on_assignee_id"
    t.index ["board_column_id"], name: "index_board_tasks_on_board_column_id"
    t.index ["board_id"], name: "index_board_tasks_on_board_id"
    t.index ["parent_task_id"], name: "index_board_tasks_on_parent_task_id"
  end

  create_table "board_view_presets", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "filters", default: {}, null: false
    t.string "name", null: false
    t.boolean "shared", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["board_id", "shared"], name: "index_board_view_presets_on_board_id_and_shared"
    t.index ["board_id", "user_id", "name"], name: "index_board_view_presets_on_board_id_and_user_id_and_name", unique: true
    t.index ["board_id"], name: "index_board_view_presets_on_board_id"
    t.index ["user_id"], name: "index_board_view_presets_on_user_id"
  end

  create_table "boards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "preset_origin"
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_boards_on_project_id", unique: true
  end

  create_table "column_transitions", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "actor_type", null: false
    t.bigint "board_task_id", null: false
    t.datetime "created_at", null: false
    t.bigint "from_column_id"
    t.bigint "to_column_id", null: false
    t.bigint "workflow_run_id"
    t.index ["actor_id"], name: "index_column_transitions_on_actor_id"
    t.index ["board_task_id"], name: "index_column_transitions_on_board_task_id"
    t.index ["from_column_id"], name: "index_column_transitions_on_from_column_id"
    t.index ["to_column_id"], name: "index_column_transitions_on_to_column_id"
    t.index ["workflow_run_id"], name: "index_column_transitions_on_workflow_run_id"
  end

  create_table "column_workflow_bindings", force: :cascade do |t|
    t.bigint "board_column_id", null: false
    t.integer "cooldown_seconds", default: 5, null: false
    t.datetime "created_at", null: false
    t.string "trigger_mode", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_id", null: false
    t.index ["board_column_id"], name: "index_column_workflow_bindings_on_board_column_id", unique: true
    t.index ["workflow_id"], name: "index_column_workflow_bindings_on_workflow_id"
  end

  create_table "companies", force: :cascade do |t|
    t.boolean "auto_accept_users", default: false, null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_domain", null: false
    t.text "logo_data"
    t.string "logo_url"
    t.string "name", null: false
    t.string "primary_color", default: "#4785FF"
    t.string "secondary_color", default: "#bb9af7"
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.string "state", null: false
    t.datetime "updated_at", null: false
    t.index ["email_domain"], name: "index_companies_on_email_domain", unique: true
    t.index ["name"], name: "index_companies_on_name", unique: true
    t.index ["slug"], name: "index_companies_on_slug", unique: true
    t.index ["state"], name: "index_companies_on_state"
  end

  create_table "config_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.text "encrypted_value"
    t.string "item_type", null: false
    t.string "name", null: false
    t.bigint "scope_id", null: false
    t.string "scope_type", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["scope_type", "scope_id", "name"], name: "index_config_items_on_scope_type_and_scope_id_and_name", unique: true
    t.index ["scope_type", "scope_id"], name: "index_config_items_on_scope_type_and_scope_id"
  end

  create_table "contact_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_contact_requests_on_created_at"
    t.index ["email"], name: "index_contact_requests_on_email"
  end

  create_table "integrations", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "connected_by_id", null: false
    t.datetime "created_at", null: false
    t.text "credentials"
    t.string "name", null: false
    t.bigint "project_id"
    t.string "provider", null: false
    t.jsonb "settings", default: {}
    t.string "status", default: "inactive", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "provider"], name: "index_integrations_on_company_id_and_provider"
    t.index ["company_id"], name: "index_integrations_on_company_id"
    t.index ["project_id", "provider"], name: "index_integrations_on_project_id_and_provider", where: "(project_id IS NOT NULL)"
    t.index ["project_id"], name: "index_integrations_on_project_id"
    t.index ["status"], name: "index_integrations_on_status"
  end

  create_table "mcp_servers", force: :cascade do |t|
    t.jsonb "args", default: []
    t.string "command"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "display_name", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "env", default: {}
    t.jsonb "headers", default: {}
    t.string "kind", default: "custom", null: false
    t.string "name", null: false
    t.bigint "scope_id"
    t.string "scope_type"
    t.string "transport", default: "sse"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["name", "scope_type", "scope_id"], name: "index_mcp_servers_on_name_and_scope_type_and_scope_id", unique: true
    t.index ["scope_type", "scope_id"], name: "index_mcp_servers_on_scope"
  end

  create_table "namespace_resource_quotas", force: :cascade do |t|
    t.string "cpu_limits"
    t.string "cpu_requests"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "max_pods"
    t.string "memory_limits"
    t.string "memory_requests"
    t.bigint "scope_id", null: false
    t.string "scope_type", null: false
    t.datetime "updated_at", null: false
    t.index ["scope_type", "scope_id"], name: "index_namespace_resource_quotas_on_scope"
    t.index ["scope_type", "scope_id"], name: "index_namespace_resource_quotas_on_scope_type_and_scope_id", unique: true
  end

  create_table "project_collaborators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id", "user_id"], name: "index_project_collaborators_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_collaborators_on_project_id"
    t.index ["user_id"], name: "index_project_collaborators_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.string "preferred_artifacts_language", default: "en"
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.string "state", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_projects_on_company_id_and_name", unique: true
    t.index ["company_id", "slug"], name: "index_projects_on_company_id_and_slug", unique: true
    t.index ["company_id"], name: "index_projects_on_company_id"
    t.index ["owner_id"], name: "index_projects_on_owner_id"
    t.index ["state"], name: "index_projects_on_state"
  end

  create_table "repositories", force: :cascade do |t|
    t.string "clone_url", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "full_name", null: false
    t.bigint "integration_id", null: false
    t.boolean "is_private", default: false
    t.datetime "last_fetched_at"
    t.text "purpose"
    t.bigint "scope_id", null: false
    t.string "scope_type", null: false
    t.string "source_branch", default: "main", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.index ["integration_id"], name: "index_repositories_on_integration_id"
    t.index ["scope_type", "scope_id", "full_name"], name: "idx_repositories_scope_full_name", unique: true
    t.index ["scope_type", "scope_id"], name: "index_repositories_on_scope_type_and_scope_id"
    t.index ["webhook_secret"], name: "index_repositories_on_webhook_secret", unique: true
  end

  create_table "session_input_assets", id: false, force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.bigint "terminal_session_id", null: false
    t.index ["terminal_session_id", "asset_id"], name: "index_session_input_assets_on_terminal_session_id_and_asset_id", unique: true
  end

  create_table "session_logs", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "file_data"
    t.bigint "file_size"
    t.string "name", null: false
    t.bigint "terminal_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["terminal_session_id"], name: "index_session_logs_on_terminal_session_id"
  end

  create_table "session_mcp_servers", id: false, force: :cascade do |t|
    t.bigint "mcp_server_id", null: false
    t.bigint "terminal_session_id", null: false
    t.index ["terminal_session_id", "mcp_server_id"], name: "idx_on_terminal_session_id_mcp_server_id_84ce6e54b4", unique: true
  end

  create_table "session_repositories", id: false, force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.bigint "terminal_session_id", null: false
    t.index ["terminal_session_id", "repository_id"], name: "idx_on_terminal_session_id_repository_id_6a57113eb8", unique: true
  end

  create_table "session_skills", id: false, force: :cascade do |t|
    t.bigint "skill_id", null: false
    t.bigint "terminal_session_id", null: false
    t.index ["terminal_session_id", "skill_id"], name: "index_session_skills_on_terminal_session_id_and_skill_id", unique: true
  end

  create_table "session_tools", id: false, force: :cascade do |t|
    t.bigint "terminal_session_id", null: false
    t.bigint "tool_id", null: false
    t.index ["terminal_session_id", "tool_id"], name: "index_session_tools_on_terminal_session_id_and_tool_id", unique: true
  end

  create_table "skills", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "install_count", default: 0
    t.string "name", null: false
    t.string "package"
    t.jsonb "references_data", default: {}
    t.bigint "scope_id"
    t.string "scope_type"
    t.string "source"
    t.string "source_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["package"], name: "index_skills_on_package"
    t.index ["scope_type", "scope_id", "name"], name: "index_skills_on_scope_type_and_scope_id_and_name", unique: true
    t.index ["scope_type", "scope_id"], name: "index_skills_on_scope_type_and_scope_id"
  end

  create_table "solid_mcp_messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "data"
    t.datetime "delivered_at"
    t.string "event_type", limit: 50, null: false
    t.string "session_id", limit: 36, null: false
    t.index ["delivered_at", "created_at"], name: "idx_solid_mcp_messages_on_delivered_and_created"
    t.index ["session_id", "id"], name: "idx_solid_mcp_messages_on_session_and_id"
  end

  create_table "step_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "error_history", default: [], null: false
    t.text "error_message"
    t.integer "retry_count", default: 0, null: false
    t.string "skip_reason"
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.bigint "step_id", null: false
    t.text "step_note"
    t.bigint "terminal_session_id"
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["step_id"], name: "index_step_runs_on_step_id"
    t.index ["terminal_session_id"], name: "index_step_runs_on_terminal_session_id"
    t.index ["workflow_run_id", "state"], name: "index_step_runs_on_workflow_run_id_and_state"
    t.index ["workflow_run_id"], name: "index_step_runs_on_workflow_run_id"
  end

  create_table "steps", force: :cascade do |t|
    t.bigint "agent_id"
    t.boolean "allow_non_interactive", default: false, null: false
    t.boolean "bmad_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.jsonb "depends_on_step_ids", default: [], null: false
    t.text "description"
    t.jsonb "input_asset_specs", default: [], null: false
    t.text "instructions"
    t.integer "max_retries", default: 0, null: false
    t.jsonb "mcp_server_ids", default: [], null: false
    t.boolean "mount_repositories", default: true, null: false
    t.string "name", null: false
    t.string "on_failure", default: "fail", null: false
    t.jsonb "output_asset_specs", default: [], null: false
    t.integer "position", null: false
    t.string "preferred_model"
    t.string "required_agent_runtime"
    t.jsonb "skill_ids", default: [], null: false
    t.string "skip_policy", default: "never", null: false
    t.jsonb "tool_ids", default: [], null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_id", null: false
    t.index ["agent_id"], name: "index_steps_on_agent_id"
    t.index ["deleted_at"], name: "index_steps_on_deleted_at"
    t.index ["workflow_id", "position"], name: "index_steps_on_workflow_id_and_position", unique: true
    t.index ["workflow_id"], name: "index_steps_on_workflow_id"
  end

  create_table "sub_step_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "data"
    t.text "note"
    t.datetime "started_at"
    t.string "state"
    t.bigint "step_run_id", null: false
    t.bigint "sub_step_id", null: false
    t.datetime "updated_at", null: false
    t.index ["step_run_id"], name: "index_sub_step_runs_on_step_run_id"
    t.index ["sub_step_id"], name: "index_sub_step_runs_on_sub_step_id"
  end

  create_table "sub_steps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.text "instructions"
    t.string "name", null: false
    t.integer "position", null: false
    t.boolean "required", default: true, null: false
    t.bigint "step_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_sub_steps_on_deleted_at"
    t.index ["step_id", "position"], name: "index_sub_steps_on_step_id_and_position"
    t.index ["step_id"], name: "index_sub_steps_on_step_id"
  end

  create_table "task_assets", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "author_type", default: "human", null: false
    t.bigint "board_task_id", null: false
    t.datetime "created_at", null: false
    t.text "file_data"
    t.string "name", null: false
    t.string "tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_task_assets_on_author_id"
    t.index ["board_task_id"], name: "index_task_assets_on_board_task_id"
  end

  create_table "task_comments", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "author_type", default: "human", null: false
    t.bigint "board_task_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "tags", default: [], array: true
    t.index ["author_id"], name: "index_task_comments_on_author_id"
    t.index ["board_task_id"], name: "index_task_comments_on_board_task_id"
  end

  create_table "task_waits", force: :cascade do |t|
    t.bigint "board_task_id", null: false
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "resolution_data", default: {}, null: false
    t.datetime "resolved_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "wait_type", null: false
    t.index "(((metadata ->> 'pipeline_id'::text))::bigint)", name: "index_task_waits_on_metadata_pipeline_id", where: "((wait_type)::text = 'gitlab_pipeline_completed'::text)"
    t.index "(((metadata ->> 'pr_number'::text))::integer)", name: "index_task_waits_on_metadata_pr_number"
    t.index "(((metadata ->> 'run_id'::text))::bigint)", name: "index_task_waits_on_metadata_run_id"
    t.index "((metadata ->> 'repo_full_name'::text))", name: "index_task_waits_on_metadata_repo_full_name"
    t.index ["board_task_id"], name: "index_task_waits_on_board_task_id"
    t.index ["creator_id"], name: "index_task_waits_on_creator_id"
    t.index ["status"], name: "index_task_waits_on_status"
    t.index ["wait_type", "status"], name: "index_task_waits_on_wait_type_and_status"
  end

  create_table "terminal_sessions", force: :cascade do |t|
    t.string "agent_type"
    t.string "artifacts_path"
    t.boolean "artifacts_reviewed", default: false
    t.bigint "cache_read_tokens", default: 0, null: false
    t.bigint "cache_write_tokens", default: 0, null: false
    t.datetime "collected_at"
    t.bigint "configured_agent_id"
    t.string "container_id"
    t.jsonb "context_metadata"
    t.bigint "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.text "initial_prompt"
    t.bigint "input_tokens", default: 0, null: false
    t.string "mcp_key"
    t.jsonb "metadata", default: {}
    t.string "mode", default: "interactive"
    t.string "models", default: [], null: false, array: true
    t.bigint "output_tokens", default: 0, null: false
    t.bigint "project_id"
    t.datetime "ready_at"
    t.string "requested_model"
    t.string "route_token"
    t.jsonb "session_config", default: {}, null: false
    t.string "session_type", null: false
    t.datetime "started_at"
    t.string "state", null: false
    t.string "temporal_run_id"
    t.string "temporal_workflow_id"
    t.bigint "total_tokens", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["configured_agent_id"], name: "index_terminal_sessions_on_configured_agent_id"
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
    t.text "content"
    t.datetime "created_at", null: false
    t.text "file_data"
    t.string "path", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tool_id", "path"], name: "index_tool_files_on_tool_id_and_path", unique: true
    t.index ["tool_id"], name: "index_tool_files_on_tool_id"
  end

  create_table "tool_results", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error"
    t.string "execution_id", null: false
    t.integer "exit_code"
    t.text "output_data"
    t.text "result_data_data"
    t.string "state", default: "processing", null: false
    t.text "stderr_data"
    t.text "stdout_data"
    t.bigint "step_run_id"
    t.bigint "terminal_session_id"
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["execution_id"], name: "index_tool_results_on_execution_id", unique: true
    t.index ["step_run_id"], name: "index_tool_results_on_step_run_id"
    t.index ["terminal_session_id"], name: "index_tool_results_on_terminal_session_id"
    t.index ["tool_id"], name: "index_tool_results_on_tool_id"
  end

  create_table "tools", force: :cascade do |t|
    t.text "command"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "display_name", null: false
    t.string "docker_image"
    t.boolean "enabled", default: true
    t.string "execution_mode", default: "container", null: false
    t.jsonb "input_schema", default: {}
    t.string "kind", default: "custom", null: false
    t.string "name", null: false
    t.jsonb "required_config_items", default: []
    t.bigint "scope_id"
    t.string "scope_type"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_tools_on_deleted_at"
    t.index ["kind"], name: "index_tools_on_kind"
    t.index ["scope_type", "scope_id", "name"], name: "index_tools_on_scope_type_and_scope_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["scope_type"], name: "index_tools_on_scope_type"
  end

  create_table "usage_statistics", force: :cascade do |t|
    t.bigint "cache_read_tokens", default: 0, null: false
    t.bigint "cache_write_tokens", default: 0, null: false
    t.bigint "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.decimal "cursor_token_fee_cents", precision: 12, scale: 6, default: "0.0"
    t.integer "events_count", default: 0, null: false
    t.jsonb "events_data", default: []
    t.bigint "input_tokens", default: 0, null: false
    t.string "models", default: [], null: false, array: true
    t.bigint "output_tokens", default: 0, null: false
    t.string "source", default: "unknown", null: false
    t.bigint "terminal_session_id", null: false
    t.bigint "tokens", default: 0, null: false
    t.decimal "total_cents_precise", precision: 12, scale: 6, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["terminal_session_id"], name: "index_usage_statistics_on_terminal_session_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.bigint "default_agent_credential_id"
    t.citext "email", null: false
    t.string "google_refresh_token"
    t.string "google_token"
    t.datetime "invited_at"
    t.bigint "invited_by_id"
    t.string "name", null: false
    t.datetime "onboarding_completed_at"
    t.string "onboarding_state", default: "step1", null: false
    t.string "password_digest"
    t.string "position"
    t.string "preferred_agent_language", default: "en"
    t.string "provider"
    t.string "role", null: false
    t.text "selected_agents", default: [], array: true
    t.string "state", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["company_id", "email"], name: "index_users_on_company_id_and_email", unique: true, where: "(company_id IS NOT NULL)"
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["default_agent_credential_id"], name: "index_users_on_default_agent_credential_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["onboarding_state"], name: "index_users_on_onboarding_state"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["state"], name: "index_users_on_state"
  end

  create_table "workflow_run_assets", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.jsonb "file_data"
    t.integer "file_size"
    t.string "name", null: false
    t.bigint "produced_by_step_run_id"
    t.string "s3_key"
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id", null: false
    t.index ["produced_by_step_run_id"], name: "index_workflow_run_assets_on_produced_by_step_run_id"
    t.index ["workflow_run_id"], name: "index_workflow_run_assets_on_workflow_run_id"
  end

  create_table "workflow_runs", force: :cascade do |t|
    t.string "agent_runtime"
    t.bigint "board_task_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "input_asset_ids", default: []
    t.string "mode", default: "interactive", null: false
    t.bigint "project_id", null: false
    t.jsonb "repository_ids", default: [], null: false
    t.jsonb "shared_context", default: {}
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.jsonb "step_overrides", default: {}, null: false
    t.integer "step_runs_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workflow_id", null: false
    t.index ["board_task_id"], name: "index_workflow_runs_on_board_task_id"
    t.index ["project_id"], name: "index_workflow_runs_on_project_id"
    t.index ["state"], name: "index_workflow_runs_on_state"
    t.index ["user_id"], name: "index_workflow_runs_on_user_id"
    t.index ["workflow_id", "state"], name: "index_workflow_runs_on_workflow_id_and_state"
    t.index ["workflow_id"], name: "index_workflow_runs_on_workflow_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.integer "scope_id", null: false
    t.string "scope_type", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_workflows_on_deleted_at"
    t.index ["scope_type", "scope_id", "name"], name: "index_workflows_on_scope_and_name_unique", unique: true, where: "(deleted_at IS NULL)"
    t.index ["scope_type", "scope_id"], name: "index_workflows_on_scope_type_and_scope_id"
    t.index ["scope_type"], name: "index_workflows_on_system_scope", where: "((scope_type)::text = 'System'::text)"
  end

  add_foreign_key "action_mcp_session_messages", "action_mcp_sessions", column: "session_id", name: "fk_action_mcp_session_messages_session_id", on_update: :cascade, on_delete: :cascade
  add_foreign_key "action_mcp_session_resources", "action_mcp_sessions", column: "session_id", on_delete: :cascade
  add_foreign_key "action_mcp_session_subscriptions", "action_mcp_sessions", column: "session_id", on_delete: :cascade
  add_foreign_key "action_mcp_session_tasks", "action_mcp_sessions", column: "session_id", name: "fk_action_mcp_session_tasks_session_id", on_update: :cascade, on_delete: :cascade
  add_foreign_key "action_mcp_sse_events", "action_mcp_sessions", column: "session_id"
  add_foreign_key "agent_credentials", "users"
  add_foreign_key "asset_versions", "assets"
  add_foreign_key "asset_versions", "users", column: "uploaded_by_id"
  add_foreign_key "assets", "terminal_sessions", on_delete: :nullify
  add_foreign_key "assets", "users", column: "created_by_id"
  add_foreign_key "board_activities", "board_tasks"
  add_foreign_key "board_activities", "boards"
  add_foreign_key "board_activities", "users", column: "actor_id"
  add_foreign_key "board_columns", "boards"
  add_foreign_key "board_tasks", "board_columns"
  add_foreign_key "board_tasks", "board_tasks", column: "parent_task_id"
  add_foreign_key "board_tasks", "boards"
  add_foreign_key "board_tasks", "users", column: "assignee_id"
  add_foreign_key "board_view_presets", "boards"
  add_foreign_key "board_view_presets", "users"
  add_foreign_key "boards", "projects"
  add_foreign_key "column_transitions", "board_columns", column: "from_column_id"
  add_foreign_key "column_transitions", "board_columns", column: "to_column_id"
  add_foreign_key "column_transitions", "board_tasks"
  add_foreign_key "column_transitions", "users", column: "actor_id"
  add_foreign_key "column_transitions", "workflow_runs"
  add_foreign_key "column_workflow_bindings", "board_columns"
  add_foreign_key "column_workflow_bindings", "workflows"
  add_foreign_key "integrations", "companies"
  add_foreign_key "integrations", "projects"
  add_foreign_key "integrations", "users", column: "connected_by_id"
  add_foreign_key "project_collaborators", "projects"
  add_foreign_key "project_collaborators", "users"
  add_foreign_key "projects", "companies"
  add_foreign_key "projects", "users", column: "owner_id"
  add_foreign_key "repositories", "integrations"
  add_foreign_key "session_input_assets", "assets", on_delete: :cascade
  add_foreign_key "session_input_assets", "terminal_sessions", on_delete: :cascade
  add_foreign_key "session_logs", "terminal_sessions", on_delete: :cascade
  add_foreign_key "session_mcp_servers", "mcp_servers", on_delete: :cascade
  add_foreign_key "session_mcp_servers", "terminal_sessions", on_delete: :cascade
  add_foreign_key "session_repositories", "repositories", on_delete: :cascade
  add_foreign_key "session_repositories", "terminal_sessions", on_delete: :cascade
  add_foreign_key "session_skills", "skills", on_delete: :cascade
  add_foreign_key "session_skills", "terminal_sessions", on_delete: :cascade
  add_foreign_key "session_tools", "terminal_sessions", on_delete: :cascade
  add_foreign_key "session_tools", "tools", on_delete: :cascade
  add_foreign_key "step_runs", "steps"
  add_foreign_key "step_runs", "terminal_sessions"
  add_foreign_key "step_runs", "workflow_runs"
  add_foreign_key "steps", "agents"
  add_foreign_key "steps", "workflows"
  add_foreign_key "sub_step_runs", "step_runs"
  add_foreign_key "sub_step_runs", "sub_steps"
  add_foreign_key "sub_steps", "steps"
  add_foreign_key "task_assets", "board_tasks"
  add_foreign_key "task_assets", "users", column: "author_id"
  add_foreign_key "task_comments", "board_tasks"
  add_foreign_key "task_comments", "users", column: "author_id"
  add_foreign_key "task_waits", "board_tasks", on_delete: :cascade
  add_foreign_key "task_waits", "users", column: "creator_id"
  add_foreign_key "terminal_sessions", "agents", column: "configured_agent_id", on_delete: :nullify
  add_foreign_key "terminal_sessions", "projects"
  add_foreign_key "terminal_sessions", "users"
  add_foreign_key "tool_files", "tools"
  add_foreign_key "tool_results", "step_runs"
  add_foreign_key "tool_results", "terminal_sessions"
  add_foreign_key "tool_results", "tools"
  add_foreign_key "usage_statistics", "terminal_sessions"
  add_foreign_key "users", "agent_credentials", column: "default_agent_credential_id"
  add_foreign_key "users", "companies"
  add_foreign_key "users", "users", column: "invited_by_id"
  add_foreign_key "workflow_run_assets", "step_runs", column: "produced_by_step_run_id", on_delete: :nullify
  add_foreign_key "workflow_run_assets", "workflow_runs"
  add_foreign_key "workflow_runs", "board_tasks"
  add_foreign_key "workflow_runs", "projects"
  add_foreign_key "workflow_runs", "users"
  add_foreign_key "workflow_runs", "workflows"
end
