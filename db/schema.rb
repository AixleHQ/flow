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

ActiveRecord::Schema[8.1].define(version: 2026_08_08_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_credentials", force: :cascade do |t|
    t.string "agent_type", null: false
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_config_data", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["agent_type"], name: "index_agent_credentials_on_agent_type"
    t.index ["company_id"], name: "index_agent_credentials_on_company_id"
    t.index ["user_id", "company_id", "agent_type"], name: "index_agent_credentials_on_user_company_agent", unique: true
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

  create_table "audits", force: :cascade do |t|
    t.string "action"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "auditable_id"
    t.string "auditable_type"
    t.text "audited_changes"
    t.string "comment"
    t.datetime "created_at"
    t.string "remote_address"
    t.string "request_uuid"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.integer "version", default: 0
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
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
    t.datetime "archived_at"
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
    t.index ["board_id", "archived_at"], name: "index_board_tasks_on_board_id_and_archived_at"
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

  create_table "catalog_search_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_searched_at"
    t.integer "search_count", default: 0, null: false
    t.string "term", null: false
    t.datetime "updated_at", null: false
    t.index ["search_count", "last_searched_at"], name: "index_catalog_search_queries_on_demand"
    t.index ["term"], name: "index_catalog_search_queries_on_term", unique: true
  end

  create_table "catalog_skills", force: :cascade do |t|
    t.jsonb "audit", default: {}, null: false
    t.string "audit_risk"
    t.datetime "audited_at"
    t.boolean "bulk_publisher", default: false, null: false
    t.string "content_hash"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "description_checked_at"
    t.boolean "featured", default: false, null: false
    t.integer "install_count", default: 0, null: false
    t.integer "installs", default: 0, null: false
    t.string "registry_id", null: false
    t.datetime "registry_synced_at"
    t.virtual "search_vector", type: :tsvector, as: "(((setweight(to_tsvector('simple'::regconfig, (COALESCE(slug, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('simple'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::\"char\")) || setweight(to_tsvector('simple'::regconfig, (COALESCE(source, ''::character varying))::text), 'B'::\"char\")) || setweight(to_tsvector('simple'::regconfig, COALESCE(description, ''::text)), 'C'::\"char\"))", stored: true
    t.string "slug", null: false
    t.string "source", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["audit_risk"], name: "index_catalog_skills_on_audit_risk"
    t.index ["description_checked_at"], name: "index_catalog_skills_on_backfill_queue", where: "(description IS NULL)"
    t.index ["featured", "bulk_publisher", "installs"], name: "index_catalog_skills_on_ranking"
    t.index ["registry_id"], name: "index_catalog_skills_on_registry_id", unique: true
    t.index ["registry_synced_at"], name: "index_catalog_skills_on_registry_synced_at"
    t.index ["search_vector"], name: "index_catalog_skills_on_search_vector", using: :gin
    t.index ["source"], name: "index_catalog_skills_on_source"
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

  create_table "company_memberships", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.bigint "default_agent_credential_id"
    t.datetime "invited_at"
    t.bigint "invited_by_id"
    t.datetime "onboarding_completed_at"
    t.string "onboarding_state", default: "step1", null: false
    t.string "position"
    t.string "preferred_agent_language", default: "en"
    t.datetime "reminded_at"
    t.string "role", default: "employee", null: false
    t.text "selected_agents", default: [], array: true
    t.string "state", default: "invited", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["company_id"], name: "index_company_memberships_on_company_id"
    t.index ["default_agent_credential_id"], name: "index_company_memberships_on_default_agent_credential_id"
    t.index ["invited_by_id"], name: "index_company_memberships_on_invited_by_id"
    t.index ["onboarding_state"], name: "index_company_memberships_on_onboarding_state"
    t.index ["state"], name: "index_company_memberships_on_state"
    t.index ["user_id", "company_id"], name: "index_company_memberships_on_user_id_and_company_id", unique: true
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

  create_table "connectors", force: :cascade do |t|
    t.boolean "bulk_publisher", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "featured", default: false, null: false
    t.integer "install_count", default: 0, null: false
    t.boolean "is_latest", default: true, null: false
    t.jsonb "manifest", default: {}, null: false
    t.string "name", null: false
    t.string "normalizer_version"
    t.datetime "registry_updated_at"
    t.string "repository_url"
    t.virtual "search_vector", type: :tsvector, as: "((setweight(to_tsvector('simple'::regconfig, (COALESCE(name, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('simple'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::\"char\")) || setweight(to_tsvector('simple'::regconfig, COALESCE(description, ''::text)), 'B'::\"char\"))", stored: true
    t.string "status", default: "active", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["bulk_publisher"], name: "index_connectors_on_bulk_publisher"
    t.index ["install_count", "featured", "registry_updated_at"], name: "index_connectors_on_ranking"
    t.index ["name"], name: "index_connectors_on_name", unique: true
    t.index ["normalizer_version"], name: "index_connectors_on_normalizer_version"
    t.index ["registry_updated_at"], name: "index_connectors_on_registry_updated_at"
    t.index ["search_vector"], name: "index_connectors_on_search_vector", using: :gin
    t.index ["status"], name: "index_connectors_on_status"
  end

  create_table "gates", force: :cascade do |t|
    t.bigint "board_task_id", null: false
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "gate_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "resolution_data", default: {}, null: false
    t.datetime "resolved_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index "(((metadata ->> 'pipeline_id'::text))::bigint)", name: "index_gates_on_metadata_pipeline_id", where: "((gate_type)::text = 'gitlab_pipeline_completed'::text)"
    t.index "(((metadata ->> 'pr_number'::text))::integer)", name: "index_gates_on_metadata_pr_number"
    t.index "(((metadata ->> 'run_id'::text))::bigint)", name: "index_gates_on_metadata_run_id"
    t.index "((metadata ->> 'repo_full_name'::text))", name: "index_gates_on_metadata_repo_full_name"
    t.index ["board_task_id"], name: "index_gates_on_board_task_id"
    t.index ["creator_id"], name: "index_gates_on_creator_id"
    t.index ["gate_type", "status"], name: "index_gates_on_gate_type_and_status"
    t.index ["status"], name: "index_gates_on_status"
  end

  create_table "integration_data", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "integration_id", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.jsonb "value", default: {}, null: false
    t.index ["expires_at"], name: "ix_integration_data_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["integration_id", "key"], name: "ix_integration_data_integration_key", unique: true
    t.index ["integration_id"], name: "index_integration_data_on_integration_id"
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
    t.string "auth_type", default: "none", null: false
    t.string "command"
    t.jsonb "connector_manifest", default: {}, null: false
    t.string "connector_name"
    t.string "connector_version"
    t.datetime "created_at", null: false
    t.string "credential_scope", default: "shared", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.jsonb "env", default: {}
    t.jsonb "headers", default: {}
    t.string "kind", default: "custom", null: false
    t.string "name", null: false
    t.bigint "scope_id"
    t.string "scope_type"
    t.jsonb "tool_drift", default: {}, null: false
    t.jsonb "tool_snapshot", default: {}, null: false
    t.datetime "tool_snapshot_at"
    t.string "transport", default: "sse"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["connector_name"], name: "index_mcp_servers_on_connector_name"
    t.index ["id"], name: "index_mcp_servers_with_tool_drift", where: "(tool_drift <> '{}'::jsonb)"
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

  create_table "oauth_clients", force: :cascade do |t|
    t.string "authorization_endpoint"
    t.string "client_id", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_client_secret"
    t.string "issuer"
    t.bigint "mcp_server_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "registration_endpoint"
    t.string "scopes"
    t.string "source", null: false
    t.string "token_endpoint"
    t.datetime "updated_at", null: false
    t.index ["issuer", "client_id"], name: "index_oauth_clients_on_issuer_and_client_id", unique: true, where: "(mcp_server_id IS NULL)"
    t.index ["mcp_server_id"], name: "index_oauth_clients_on_mcp_server_id", unique: true, where: "(mcp_server_id IS NOT NULL)"
    t.index ["source"], name: "index_oauth_clients_on_source"
  end

  create_table "oauth_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_access_token"
    t.text "encrypted_refresh_token"
    t.datetime "expires_at"
    t.datetime "last_refreshed_at"
    t.bigint "mcp_server_id"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "oauth_client_id", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.string "provider", null: false
    t.string "refresh_error"
    t.integer "refresh_failure_count", default: 0, null: false
    t.string "scopes"
    t.string "status", default: "pending", null: false
    t.string "token_type", default: "Bearer"
    t.datetime "updated_at", null: false
    t.index ["mcp_server_id"], name: "index_oauth_credentials_on_mcp_server_id"
    t.index ["oauth_client_id"], name: "index_oauth_credentials_on_oauth_client_id"
    t.index ["owner_type", "owner_id", "oauth_client_id", "provider", "mcp_server_id"], name: "idx_oauth_credentials_unique_owner_client", unique: true
    t.index ["owner_type", "owner_id", "provider"], name: "idx_on_owner_type_owner_id_provider_1db0e9274f"
    t.index ["owner_type", "owner_id"], name: "index_oauth_credentials_on_owner"
    t.index ["status", "expires_at"], name: "index_oauth_credentials_on_status_and_expires_at"
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

  create_table "received_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type"
    t.string "idempotency_key", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.bigint "webhook_endpoint_id", null: false
    t.index ["webhook_endpoint_id", "idempotency_key"], name: "index_received_webhooks_on_endpoint_and_idempotency_key", unique: true
    t.index ["webhook_endpoint_id"], name: "index_received_webhooks_on_webhook_endpoint_id"
  end

  create_table "repositories", force: :cascade do |t|
    t.string "clone_url", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "full_name", null: false
    t.bigint "integration_id"
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
    t.string "content_hash"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "install_count", default: 0
    t.string "name", null: false
    t.string "origin", default: "registry", null: false
    t.string "package"
    t.bigint "scope_id"
    t.string "scope_type"
    t.string "source"
    t.string "source_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["origin"], name: "index_skills_on_origin"
    t.index ["package"], name: "index_skills_on_package"
    t.index ["scope_type", "scope_id", "name"], name: "index_skills_on_scope_type_and_scope_id_and_name", unique: true
    t.index ["scope_type", "scope_id"], name: "index_skills_on_scope_type_and_scope_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "step_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_category"
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
    t.jsonb "asset_ids", default: [], null: false
    t.boolean "bmad_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.jsonb "depends_on_step_ids", default: [], null: false
    t.jsonb "input_asset_specs", default: [], null: false
    t.text "instructions"
    t.integer "max_retries", default: 0, null: false
    t.jsonb "mcp_server_ids", default: [], null: false
    t.string "name", null: false
    t.string "on_failure", default: "fail", null: false
    t.jsonb "output_asset_specs", default: [], null: false
    t.integer "position", null: false
    t.string "preferred_model"
    t.jsonb "repository_ids", default: [], null: false
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

  create_table "terminal_sessions", force: :cascade do |t|
    t.string "agent_type"
    t.string "artifacts_path"
    t.boolean "artifacts_reviewed", default: false
    t.bigint "cache_read_tokens", default: 0, null: false
    t.bigint "cache_write_tokens", default: 0, null: false
    t.datetime "collected_at"
    t.bigint "company_id"
    t.bigint "configured_agent_id"
    t.string "container_id"
    t.jsonb "context_metadata"
    t.bigint "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "finishing_at"
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
    t.index ["company_id"], name: "index_terminal_sessions_on_company_id"
    t.index ["configured_agent_id"], name: "index_terminal_sessions_on_configured_agent_id"
    t.index ["mcp_key"], name: "index_terminal_sessions_on_mcp_key", unique: true
    t.index ["project_id"], name: "index_terminal_sessions_on_project_id"
    t.index ["route_token"], name: "index_terminal_sessions_on_route_token", unique: true
    t.index ["session_type"], name: "index_terminal_sessions_on_session_type"
    t.index ["state"], name: "index_terminal_sessions_on_state"
    t.index ["temporal_workflow_id"], name: "index_terminal_sessions_on_temporal_workflow_id"
    t.index ["user_id", "created_at"], name: "index_terminal_sessions_on_user_id_and_created_at"
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
    t.string "definition_digest"
    t.datetime "deleted_at"
    t.text "description"
    t.string "display_name", null: false
    t.string "docker_image"
    t.string "docker_image_digest"
    t.boolean "enabled", default: true
    t.string "execution_mode", default: "container", null: false
    t.jsonb "input_schema", default: {}
    t.string "name", null: false
    t.jsonb "required_config_items", default: []
    t.string "requires_integration"
    t.bigint "scope_id"
    t.string "scope_type"
    t.string "source", default: "db", null: false
    t.jsonb "tags", default: [], null: false
    t.datetime "updated_at", null: false
    t.boolean "user_attachable", default: true, null: false
    t.index ["deleted_at"], name: "index_tools_on_deleted_at"
    t.index ["name"], name: "index_tools_on_name_where_source_code", unique: true, where: "(((source)::text = 'code'::text) AND (deleted_at IS NULL))"
    t.index ["scope_type", "scope_id", "name"], name: "index_tools_on_scope_type_and_scope_id_and_name", unique: true, where: "(deleted_at IS NULL)"
  end

  add_check_constraint "tools", "name::text !~~ 'mcp\\_\\_%'::text", name: "tools_name_not_managed_namespace", validate: false

  create_table "trigger_bindings", force: :cascade do |t|
    t.integer "cooldown_seconds", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.boolean "enabled", default: true, null: false
    t.string "event_type", null: false
    t.jsonb "filter_predicate", default: {}, null: false
    t.string "name"
    t.bigint "project_id", null: false
    t.jsonb "schedule_config", default: {}, null: false
    t.bigint "subject_column_id"
    t.string "subject_policy", default: "none", null: false
    t.string "subject_title_template"
    t.string "trigger_mode", default: "auto", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_id", null: false
    t.index ["created_by_id"], name: "index_trigger_bindings_on_created_by_id"
    t.index ["project_id", "event_type", "enabled"], name: "idx_on_project_id_event_type_enabled_44a9c97a71"
    t.index ["project_id"], name: "index_trigger_bindings_on_project_id"
    t.index ["subject_column_id"], name: "index_trigger_bindings_on_subject_column_id"
    t.index ["workflow_id"], name: "index_trigger_bindings_on_workflow_id"
  end

  create_table "trigger_dispatches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dedup_key", null: false
    t.jsonb "detail", default: {}, null: false
    t.string "source"
    t.string "status", default: "matched", null: false
    t.bigint "trigger_binding_id"
    t.bigint "trigger_event_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id"
    t.index ["dedup_key"], name: "index_trigger_dispatches_on_dedup_key", unique: true
    t.index ["trigger_binding_id"], name: "index_trigger_dispatches_on_trigger_binding_id"
    t.index ["trigger_event_id"], name: "index_trigger_dispatches_on_trigger_event_id"
    t.index ["workflow_run_id"], name: "index_trigger_dispatches_on_workflow_run_id"
  end

  create_table "trigger_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.bigint "board_task_id"
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "dedup_key"
    t.datetime "dispatched_at"
    t.string "event_type", null: false
    t.datetime "occurred_at"
    t.bigint "project_id"
    t.integer "relay_attempts", default: 0, null: false
    t.string "relay_error"
    t.string "relay_state", default: "dispatched", null: false
    t.string "source"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_trigger_events_on_actor_id"
    t.index ["board_task_id"], name: "index_trigger_events_on_board_task_id"
    t.index ["company_id", "event_type"], name: "index_trigger_events_on_company_id_and_event_type"
    t.index ["dedup_key"], name: "index_trigger_events_on_dedup_key_unique", unique: true, where: "(dedup_key IS NOT NULL)"
    t.index ["event_type"], name: "index_trigger_events_on_event_type"
    t.index ["project_id", "event_type"], name: "index_trigger_events_on_project_id_and_event_type"
    t.index ["relay_state", "created_at"], name: "index_trigger_events_pending_relay", where: "((relay_state)::text = ANY (ARRAY[('pending'::character varying)::text, ('dispatching'::character varying)::text]))"
  end

  create_table "usage_statistics", force: :cascade do |t|
    t.bigint "cache_read_tokens", default: 0, null: false
    t.bigint "cache_write_tokens", default: 0, null: false
    t.bigint "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
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
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.citext "email", null: false
    t.bigint "last_company_id"
    t.string "mcp_token_digest"
    t.datetime "mcp_token_last_used_at"
    t.string "name", null: false
    t.string "password_digest"
    t.string "provider"
    t.boolean "share_active_sessions", default: false, null: false
    t.boolean "share_completed_sessions", default: true, null: false
    t.string "state", null: false
    t.boolean "super_admin", default: false, null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at", where: "(deleted_at IS NOT NULL)"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["mcp_token_digest"], name: "index_users_on_mcp_token_digest", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["state"], name: "index_users_on_state"
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.bigint "company_id"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.boolean "enabled", default: true, null: false
    t.text "encrypted_secret"
    t.bigint "project_id"
    t.string "provider", default: "generic", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "verification_strategy", default: "none", null: false
    t.index ["company_id"], name: "index_webhook_endpoints_on_company_id"
    t.index ["created_by_id"], name: "index_webhook_endpoints_on_created_by_id"
    t.index ["project_id"], name: "index_webhook_endpoints_on_project_id"
    t.index ["slug"], name: "index_webhook_endpoints_on_slug", unique: true
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
    t.bigint "failed_agent_credential_id"
    t.string "failure_reason"
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
    t.index ["failed_agent_credential_id"], name: "index_workflow_runs_on_failed_agent_credential_id"
    t.index ["project_id"], name: "index_workflow_runs_on_project_id"
    t.index ["state"], name: "index_workflow_runs_on_state"
    t.index ["user_id", "created_at"], name: "index_workflow_runs_on_user_id_and_created_at"
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
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.integer "scope_id", null: false
    t.string "scope_type", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_workflows_on_deleted_at"
    t.index ["published_at"], name: "index_workflows_on_published_at", where: "(published_at IS NOT NULL)"
    t.index ["published_by_id"], name: "index_workflows_on_published_by_id"
    t.index ["scope_type", "scope_id", "name"], name: "index_workflows_on_scope_and_name_unique", unique: true, where: "(deleted_at IS NULL)"
    t.index ["scope_type", "scope_id"], name: "index_workflows_on_scope_type_and_scope_id"
    t.index ["scope_type"], name: "index_workflows_on_system_scope", where: "((scope_type)::text = 'System'::text)"
  end

  add_foreign_key "agent_credentials", "companies"
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
  add_foreign_key "company_memberships", "agent_credentials", column: "default_agent_credential_id", on_delete: :nullify
  add_foreign_key "company_memberships", "companies"
  add_foreign_key "company_memberships", "users"
  add_foreign_key "company_memberships", "users", column: "invited_by_id"
  add_foreign_key "gates", "board_tasks", on_delete: :cascade
  add_foreign_key "gates", "users", column: "creator_id"
  add_foreign_key "integration_data", "integrations", on_delete: :cascade
  add_foreign_key "integrations", "companies"
  add_foreign_key "integrations", "projects"
  add_foreign_key "integrations", "users", column: "connected_by_id"
  add_foreign_key "oauth_clients", "mcp_servers"
  add_foreign_key "oauth_credentials", "mcp_servers"
  add_foreign_key "oauth_credentials", "oauth_clients"
  add_foreign_key "project_collaborators", "projects"
  add_foreign_key "project_collaborators", "users"
  add_foreign_key "projects", "companies"
  add_foreign_key "projects", "users", column: "owner_id"
  add_foreign_key "received_webhooks", "webhook_endpoints", on_delete: :cascade
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
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "step_runs", "steps"
  add_foreign_key "step_runs", "terminal_sessions"
  add_foreign_key "step_runs", "workflow_runs"
  add_foreign_key "steps", "agents", on_delete: :nullify
  add_foreign_key "steps", "workflows"
  add_foreign_key "sub_step_runs", "step_runs"
  add_foreign_key "sub_step_runs", "sub_steps"
  add_foreign_key "sub_steps", "steps"
  add_foreign_key "task_assets", "board_tasks"
  add_foreign_key "task_assets", "users", column: "author_id"
  add_foreign_key "task_comments", "board_tasks"
  add_foreign_key "task_comments", "users", column: "author_id"
  add_foreign_key "terminal_sessions", "agents", column: "configured_agent_id", on_delete: :nullify
  add_foreign_key "terminal_sessions", "companies"
  add_foreign_key "terminal_sessions", "projects"
  add_foreign_key "terminal_sessions", "users"
  add_foreign_key "tool_files", "tools"
  add_foreign_key "tool_results", "step_runs", on_delete: :nullify
  add_foreign_key "tool_results", "terminal_sessions"
  add_foreign_key "tool_results", "tools"
  add_foreign_key "trigger_bindings", "board_columns", column: "subject_column_id", on_delete: :nullify
  add_foreign_key "trigger_bindings", "projects", on_delete: :cascade
  add_foreign_key "trigger_bindings", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "trigger_bindings", "workflows", on_delete: :cascade
  add_foreign_key "trigger_dispatches", "trigger_bindings", on_delete: :nullify
  add_foreign_key "trigger_dispatches", "trigger_events", on_delete: :cascade
  add_foreign_key "trigger_dispatches", "workflow_runs", on_delete: :nullify
  add_foreign_key "trigger_events", "board_tasks", on_delete: :nullify
  add_foreign_key "trigger_events", "projects", on_delete: :nullify
  add_foreign_key "trigger_events", "users", column: "actor_id"
  add_foreign_key "usage_statistics", "terminal_sessions"
  add_foreign_key "webhook_endpoints", "companies", on_delete: :cascade
  add_foreign_key "webhook_endpoints", "projects", on_delete: :cascade
  add_foreign_key "webhook_endpoints", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "workflow_run_assets", "step_runs", column: "produced_by_step_run_id", on_delete: :nullify
  add_foreign_key "workflow_run_assets", "workflow_runs"
  add_foreign_key "workflow_runs", "agent_credentials", column: "failed_agent_credential_id", on_delete: :nullify
  add_foreign_key "workflow_runs", "board_tasks"
  add_foreign_key "workflow_runs", "projects"
  add_foreign_key "workflow_runs", "users"
  add_foreign_key "workflow_runs", "workflows"
  add_foreign_key "workflows", "users", column: "published_by_id"
end
