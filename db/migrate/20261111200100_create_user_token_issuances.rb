# frozen_string_literal: true

# docs/design/github-user-identity.md §3.2. One immutable row per token an agent
# was handed on a user's behalf: the audit trail and the source of the values the
# session's log redaction masks.
class CreateUserTokenIssuances < ActiveRecord::Migration[8.1]
  def change
    create_table :user_token_issuances do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :acting_for_user, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :session_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :tool_name, null: false
      t.string :provider, null: false
      t.references :oauth_credential, foreign_key: { on_delete: :nullify }
      t.text :encrypted_token, null: false
      t.string :token_last_eight
      t.string :target_login, null: false
      t.string :repository_full_names, array: true, null: false, default: []
      t.datetime :expires_at
      t.datetime :created_at, null: false

      t.index %i[acting_for_user_id created_at], name: "index_user_token_issuances_on_user_and_created_at"
    end

    add_foreign_key :user_token_issuances, :projects, column: %i[project_id company_id], primary_key: %i[id company_id],
                                                      on_delete: :cascade, name: "fk_user_token_issuances_project_company"
  end
end
