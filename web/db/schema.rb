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

ActiveRecord::Schema[8.0].define(version: 2025_12_23_133248) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "account_users", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "status", default: "invited"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "invitation_token"
    t.index ["account_id", "user_id"], name: "index_account_users_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["invitation_token"], name: "index_account_users_on_invitation_token", unique: true
    t.index ["status"], name: "index_account_users_on_status"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "accounts_presets", id: false, force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "preset_id", null: false
  end

  create_table "assets", force: :cascade do |t|
    t.string "name"
    t.string "type"
    t.text "file_data"
    t.bigint "workspace_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "size"
    t.string "format"
    t.bigint "integration_id"
    t.string "ai_engine_state"
    t.text "description"
    t.string "status", default: "draft"
    t.jsonb "metadata", default: {}
    t.bigint "codebase_indexing_model_id"
    t.bigint "codebase_reporting_model_id"
    t.bigint "document_analysis_model_id"
    t.bigint "ui_vision_model_id"
    t.bigint "ui_critic_model_id"
    t.bigint "ui_summary_model_id"
    t.index ["codebase_indexing_model_id"], name: "index_assets_on_codebase_indexing_model_id"
    t.index ["codebase_reporting_model_id"], name: "index_assets_on_codebase_reporting_model_id"
    t.index ["document_analysis_model_id"], name: "index_assets_on_document_analysis_model_id"
    t.index ["integration_id"], name: "index_assets_on_integration_id"
    t.index ["ui_critic_model_id"], name: "index_assets_on_ui_critic_model_id"
    t.index ["ui_summary_model_id"], name: "index_assets_on_ui_summary_model_id"
    t.index ["ui_vision_model_id"], name: "index_assets_on_ui_vision_model_id"
    t.index ["workspace_id"], name: "index_assets_on_workspace_id"
  end

  create_table "audits", force: :cascade do |t|
    t.integer "auditable_id"
    t.string "auditable_type"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.text "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at"
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "code_base_items", force: :cascade do |t|
    t.bigint "code_base_id", null: false
    t.string "relative_path"
    t.string "filename"
    t.integer "size"
    t.string "file_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "file_data"
    t.string "mime_info"
    t.jsonb "metadata", default: {}
    t.string "full_path"
    t.string "repo_provider"
    t.string "repo_file_url"
    t.index ["code_base_id", "full_path"], name: "index_code_base_items_on_code_base_id_and_full_path", unique: true
    t.index ["code_base_id"], name: "index_code_base_items_on_code_base_id"
  end

  create_table "code_bases", force: :cascade do |t|
    t.string "name"
    t.bigint "asset_id", null: false
    t.string "status", default: "draft", null: false
    t.integer "total_files", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "processed_files", default: 0, null: false
    t.integer "skipped_files", default: 0, null: false
    t.integer "failed_files", default: 0, null: false
    t.jsonb "file_tree"
    t.jsonb "processing_stats"
    t.index ["asset_id"], name: "index_code_bases_on_asset_id"
  end

  create_table "code_reports", force: :cascade do |t|
    t.string "ai_engine_state"
    t.bigint "code_base_id", null: false
    t.bigint "asset_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.index ["asset_id"], name: "index_code_reports_on_asset_id"
    t.index ["code_base_id"], name: "index_code_reports_on_code_base_id"
  end

  create_table "confluence_pages", force: :cascade do |t|
    t.string "confluence_id", null: false
    t.string "title", null: false
    t.string "space_id", null: false
    t.bigint "confluence_space_id", null: false
    t.bigint "integration_id", null: false
    t.jsonb "sync_metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confluence_space_id"], name: "index_confluence_pages_on_confluence_space_id"
    t.index ["integration_id", "confluence_id"], name: "index_confluence_pages_on_integration_id_and_confluence_id", unique: true
    t.index ["integration_id"], name: "index_confluence_pages_on_integration_id"
  end

  create_table "confluence_spaces", force: :cascade do |t|
    t.string "confluence_id", null: false
    t.string "confluence_key", null: false
    t.string "name", null: false
    t.bigint "integration_id", null: false
    t.bigint "asset_id"
    t.string "sync_status", default: "not_synced", null: false
    t.jsonb "sync_progress", default: {}, null: false
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_confluence_spaces_on_asset_id"
    t.index ["confluence_id"], name: "index_confluence_spaces_on_confluence_id"
    t.index ["integration_id", "confluence_key"], name: "index_confluence_spaces_on_integration_id_and_confluence_key", unique: true
    t.index ["integration_id"], name: "index_confluence_spaces_on_integration_id"
  end

  create_table "diagrams", force: :cascade do |t|
    t.string "ai_engine_state"
    t.string "name"
    t.string "type"
    t.string "kind"
    t.text "content"
    t.bigint "version_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.index ["version_id"], name: "index_diagrams_on_version_id"
  end

  create_table "domains", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.text "justification"
    t.string "ai_engine_state"
    t.bigint "version_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.string "status"
    t.index ["version_id"], name: "index_domains_on_version_id"
  end

  create_table "external_specifications", force: :cascade do |t|
    t.string "name"
    t.bigint "workspace_id"
    t.string "status"
    t.text "file_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id"], name: "index_external_specifications_on_workspace_id"
  end

  create_table "features", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.text "justification"
    t.string "ai_engine_state"
    t.bigint "domain_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.text "technical_description"
    t.string "status"
    t.index ["domain_id"], name: "index_features_on_domain_id"
  end

  create_table "image_collection_items", force: :cascade do |t|
    t.bigint "image_collection_id", null: false
    t.string "relative_path"
    t.string "filename"
    t.integer "size"
    t.string "file_type"
    t.text "file_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mime_info"
    t.string "full_path"
    t.jsonb "metadata", default: {}
    t.text "description"
    t.index ["image_collection_id", "full_path"], name: "idx_on_image_collection_id_full_path_93ad0b14e7", unique: true
    t.index ["image_collection_id"], name: "index_image_collection_items_on_image_collection_id"
  end

  create_table "image_collections", force: :cascade do |t|
    t.string "name"
    t.bigint "asset_id", null: false
    t.string "status", default: "draft", null: false
    t.integer "total_files", default: 0, null: false
    t.integer "processed_files", default: 0, null: false
    t.integer "skipped_files", default: 0, null: false
    t.integer "failed_files", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "file_tree"
    t.jsonb "processing_stats"
    t.index ["asset_id"], name: "index_image_collections_on_asset_id"
  end

  create_table "integration_repos", force: :cascade do |t|
    t.bigint "integration_id", null: false
    t.bigint "asset_id"
    t.string "name", null: false
    t.string "owner", null: false
    t.boolean "private", default: true, null: false
    t.string "html_url"
    t.text "archive_link"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "draft", null: false
    t.string "default_branch", default: "main"
    t.bigint "codebase_indexing_model_id"
    t.bigint "codebase_reporting_model_id"
    t.index ["asset_id"], name: "index_integration_repos_on_asset_id"
    t.index ["codebase_indexing_model_id"], name: "index_integration_repos_on_codebase_indexing_model_id"
    t.index ["codebase_reporting_model_id"], name: "index_integration_repos_on_codebase_reporting_model_id"
    t.index ["integration_id", "name"], name: "index_integration_repos_on_integration_id_and_name", unique: true
    t.index ["integration_id"], name: "index_integration_repos_on_integration_id"
  end

  create_table "integration_users", force: :cascade do |t|
    t.bigint "integration_id", null: false
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.jsonb "params", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_id"], name: "index_integration_users_on_integration_id"
    t.index ["user_id", "integration_id"], name: "index_integration_users_on_user_id_and_integration_id", unique: true
    t.index ["user_id"], name: "index_integration_users_on_user_id"
  end

  create_table "integrations", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "kind", default: "git", null: false
    t.string "provider", default: "github", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "params"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.index ["workspace_id"], name: "index_integrations_on_workspace_id"
  end

  create_table "jira_issues", force: :cascade do |t|
    t.string "exportable_type", null: false
    t.bigint "exportable_id", null: false
    t.bigint "integration_id", null: false
    t.bigint "jira_project_id"
    t.string "jira_issue_key", null: false
    t.string "jira_issue_id", null: false
    t.string "jira_issue_type", null: false
    t.jsonb "sync_metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exportable_type", "exportable_id", "integration_id"], name: "index_jira_issues_on_exportable_and_integration", unique: true
    t.index ["exportable_type", "exportable_id"], name: "index_jira_issues_on_exportable"
    t.index ["integration_id", "jira_issue_key"], name: "index_jira_issues_on_integration_id_and_jira_issue_key", unique: true
    t.index ["integration_id"], name: "index_jira_issues_on_integration_id"
    t.index ["jira_project_id"], name: "index_jira_issues_on_jira_project_id"
  end

  create_table "jira_projects", force: :cascade do |t|
    t.string "jira_id", null: false
    t.string "jira_key", null: false
    t.string "name", null: false
    t.bigint "integration_id", null: false
    t.jsonb "issue_types", default: [], null: false
    t.string "sync_status", default: "not_synced", null: false
    t.datetime "last_synced_at"
    t.jsonb "sync_progress", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_id", "jira_key"], name: "index_jira_projects_on_integration_id_and_jira_key", unique: true
    t.index ["integration_id"], name: "index_jira_projects_on_integration_id"
    t.index ["jira_id"], name: "index_jira_projects_on_jira_id"
    t.index ["sync_status"], name: "index_jira_projects_on_sync_status"
  end

  create_table "model_definitions", force: :cascade do |t|
    t.jsonb "raw"
    t.string "identifier"
    t.string "canonical_slug"
    t.string "name"
    t.bigint "created"
    t.string "description"
    t.integer "context_length"
    t.jsonb "pricing"
    t.jsonb "supported_parameters"
    t.jsonb "default_parameters"
    t.string "modality"
    t.jsonb "input_modalities"
    t.jsonb "output_modalities"
    t.jsonb "per_request_limits"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "presets", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "default", default: false, null: false
    t.boolean "public", default: false, null: false
    t.bigint "codebase_indexing_model_id"
    t.bigint "codebase_reporting_model_id"
    t.bigint "document_analysis_model_id"
    t.bigint "ui_vision_model_id"
    t.bigint "ui_critic_model_id"
    t.bigint "ui_summary_model_id"
    t.bigint "domain_analysis_model_id"
    t.bigint "feature_extraction_model_id"
    t.bigint "user_story_model_id"
    t.bigint "use_case_model_id"
    t.bigint "diagram_model_id"
    t.bigint "data_flow_model_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["codebase_indexing_model_id"], name: "index_presets_on_codebase_indexing_model_id"
    t.index ["codebase_reporting_model_id"], name: "index_presets_on_codebase_reporting_model_id"
    t.index ["data_flow_model_id"], name: "index_presets_on_data_flow_model_id"
    t.index ["default"], name: "index_presets_on_default"
    t.index ["diagram_model_id"], name: "index_presets_on_diagram_model_id"
    t.index ["document_analysis_model_id"], name: "index_presets_on_document_analysis_model_id"
    t.index ["domain_analysis_model_id"], name: "index_presets_on_domain_analysis_model_id"
    t.index ["feature_extraction_model_id"], name: "index_presets_on_feature_extraction_model_id"
    t.index ["public"], name: "index_presets_on_public"
    t.index ["ui_critic_model_id"], name: "index_presets_on_ui_critic_model_id"
    t.index ["ui_summary_model_id"], name: "index_presets_on_ui_summary_model_id"
    t.index ["ui_vision_model_id"], name: "index_presets_on_ui_vision_model_id"
    t.index ["use_case_model_id"], name: "index_presets_on_use_case_model_id"
    t.index ["user_story_model_id"], name: "index_presets_on_user_story_model_id"
  end

  create_table "presets_workspaces", id: false, force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "preset_id", null: false
  end

  create_table "quality_issues", force: :cascade do |t|
    t.bigint "code_base_item_id", null: false
    t.string "title", null: false
    t.text "evidence", null: false
    t.string "severity", null: false
    t.text "suggested_fix"
    t.text "why_it_matters"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_base_item_id"], name: "index_quality_issues_on_code_base_item_id"
    t.index ["severity"], name: "index_quality_issues_on_severity"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.bigint "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id", unique: true, nulls_not_distinct: true
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "sections", force: :cascade do |t|
    t.string "ai_engine_state"
    t.string "name"
    t.integer "order"
    t.text "description"
    t.text "justification"
    t.bigint "sectionable_id"
    t.string "sectionable_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.index ["sectionable_id", "sectionable_type", "order"], name: "idx_on_sectionable_id_sectionable_type_order_f4f7a5e83e", unique: true
    t.index ["sectionable_id", "sectionable_type"], name: "index_sections_on_sectionable_id_and_sectionable_type"
  end

  create_table "specification_assets", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.bigint "specification_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "importance_level"
    t.index ["asset_id"], name: "index_specification_assets_on_asset_id"
    t.index ["specification_id"], name: "index_specification_assets_on_specification_id"
  end

  create_table "specification_users", force: :cascade do |t|
    t.bigint "specification_id", null: false
    t.bigint "user_id", null: false
    t.string "mcp_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mcp_token"], name: "index_specification_users_on_mcp_token", unique: true
    t.index ["specification_id", "user_id"], name: "index_specification_users_on_specification_id_and_user_id", unique: true
    t.index ["specification_id"], name: "index_specification_users_on_specification_id"
    t.index ["user_id"], name: "index_specification_users_on_user_id"
  end

  create_table "specification_versions", force: :cascade do |t|
    t.bigint "specification_id", null: false
    t.string "version_tag"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ai_engine_state"
    t.jsonb "progress", default: {}
    t.string "status", default: "draft"
    t.index ["specification_id"], name: "index_specification_versions_on_specification_id"
  end

  create_table "specifications", force: :cascade do |t|
    t.string "name"
    t.string "status"
    t.bigint "workspace_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.text "prompt"
    t.bigint "domain_analysis_model_id"
    t.bigint "feature_extraction_model_id"
    t.bigint "user_story_model_id"
    t.bigint "use_case_model_id"
    t.bigint "diagram_model_id"
    t.bigint "data_flow_model_id"
    t.index ["data_flow_model_id"], name: "index_specifications_on_data_flow_model_id"
    t.index ["diagram_model_id"], name: "index_specifications_on_diagram_model_id"
    t.index ["domain_analysis_model_id"], name: "index_specifications_on_domain_analysis_model_id"
    t.index ["feature_extraction_model_id"], name: "index_specifications_on_feature_extraction_model_id"
    t.index ["use_case_model_id"], name: "index_specifications_on_use_case_model_id"
    t.index ["user_story_model_id"], name: "index_specifications_on_user_story_model_id"
    t.index ["workspace_id"], name: "index_specifications_on_workspace_id"
  end

  create_table "use_cases", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.text "justification"
    t.string "ai_engine_state"
    t.bigint "user_story_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "data"
    t.text "gherkin_syntax"
    t.integer "order"
    t.string "status"
    t.index ["user_story_id"], name: "index_use_cases_on_user_story_id"
  end

  create_table "user_roles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.string "state"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "user_stories", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.text "justification"
    t.string "ai_engine_state"
    t.bigint "feature_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.text "technical_description"
    t.string "status"
    t.index ["feature_id"], name: "index_user_stories_on_feature_id"
  end

  create_table "users", force: :cascade do |t|
    t.citext "email"
    t.string "name"
    t.string "status"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "otp_secret"
    t.datetime "last_otp_at"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "name"
    t.string "status"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ai_engine_syncable", default: true
    t.index ["account_id"], name: "index_workspaces_on_account_id"
  end

  add_foreign_key "account_users", "accounts", on_delete: :cascade
  add_foreign_key "account_users", "users", on_delete: :cascade
  add_foreign_key "assets", "integrations", on_delete: :cascade
  add_foreign_key "assets", "model_definitions", column: "codebase_indexing_model_id", on_delete: :nullify
  add_foreign_key "assets", "model_definitions", column: "codebase_reporting_model_id", on_delete: :nullify
  add_foreign_key "assets", "model_definitions", column: "document_analysis_model_id", on_delete: :nullify
  add_foreign_key "assets", "model_definitions", column: "ui_critic_model_id", on_delete: :nullify
  add_foreign_key "assets", "model_definitions", column: "ui_summary_model_id", on_delete: :nullify
  add_foreign_key "assets", "model_definitions", column: "ui_vision_model_id", on_delete: :nullify
  add_foreign_key "assets", "workspaces", on_delete: :cascade
  add_foreign_key "code_base_items", "code_bases", on_delete: :cascade
  add_foreign_key "code_bases", "assets", on_delete: :cascade
  add_foreign_key "code_reports", "assets", on_delete: :cascade
  add_foreign_key "code_reports", "code_bases", on_delete: :cascade
  add_foreign_key "confluence_pages", "confluence_spaces", on_delete: :cascade
  add_foreign_key "confluence_pages", "integrations", on_delete: :cascade
  add_foreign_key "confluence_spaces", "assets", on_delete: :nullify
  add_foreign_key "confluence_spaces", "integrations", on_delete: :cascade
  add_foreign_key "diagrams", "specification_versions", column: "version_id", on_delete: :cascade
  add_foreign_key "domains", "specification_versions", column: "version_id", on_delete: :cascade
  add_foreign_key "external_specifications", "workspaces", on_delete: :cascade
  add_foreign_key "features", "domains", on_delete: :cascade
  add_foreign_key "image_collection_items", "image_collections", on_delete: :cascade
  add_foreign_key "image_collections", "assets", on_delete: :cascade
  add_foreign_key "integration_repos", "assets", on_delete: :cascade
  add_foreign_key "integration_repos", "integrations", on_delete: :cascade
  add_foreign_key "integration_repos", "model_definitions", column: "codebase_indexing_model_id", on_delete: :nullify
  add_foreign_key "integration_repos", "model_definitions", column: "codebase_reporting_model_id", on_delete: :nullify
  add_foreign_key "integration_users", "integrations", on_delete: :cascade
  add_foreign_key "integration_users", "users", on_delete: :cascade
  add_foreign_key "integrations", "workspaces", on_delete: :cascade
  add_foreign_key "jira_issues", "integrations", on_delete: :cascade
  add_foreign_key "jira_issues", "jira_projects", on_delete: :cascade
  add_foreign_key "jira_projects", "integrations", on_delete: :cascade
  add_foreign_key "presets", "model_definitions", column: "codebase_indexing_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "codebase_reporting_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "data_flow_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "diagram_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "document_analysis_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "domain_analysis_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "feature_extraction_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "ui_critic_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "ui_summary_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "ui_vision_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "use_case_model_id", on_delete: :nullify
  add_foreign_key "presets", "model_definitions", column: "user_story_model_id", on_delete: :nullify
  add_foreign_key "quality_issues", "code_base_items", on_delete: :cascade
  add_foreign_key "specification_assets", "assets", on_delete: :cascade
  add_foreign_key "specification_assets", "specifications", on_delete: :cascade
  add_foreign_key "specification_users", "specifications", on_delete: :cascade
  add_foreign_key "specification_users", "users", on_delete: :cascade
  add_foreign_key "specification_versions", "specifications", on_delete: :cascade
  add_foreign_key "specifications", "model_definitions", column: "data_flow_model_id", on_delete: :nullify
  add_foreign_key "specifications", "model_definitions", column: "diagram_model_id", on_delete: :nullify
  add_foreign_key "specifications", "model_definitions", column: "domain_analysis_model_id", on_delete: :nullify
  add_foreign_key "specifications", "model_definitions", column: "feature_extraction_model_id", on_delete: :nullify
  add_foreign_key "specifications", "model_definitions", column: "use_case_model_id", on_delete: :nullify
  add_foreign_key "specifications", "model_definitions", column: "user_story_model_id", on_delete: :nullify
  add_foreign_key "specifications", "workspaces", on_delete: :cascade
  add_foreign_key "use_cases", "user_stories", on_delete: :cascade
  add_foreign_key "user_roles", "roles", on_delete: :cascade
  add_foreign_key "user_roles", "users", on_delete: :cascade
  add_foreign_key "user_stories", "features", on_delete: :cascade
  add_foreign_key "workspaces", "accounts", on_delete: :cascade
end
