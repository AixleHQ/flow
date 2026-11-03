# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.2 and §2.3, the columns §15 task 5a
# reads and writes: a `manual` machine registers through the runner gateway and
# holds an access/refresh pair. Both tables carry company_id directly, like
# runners, and the §2 composite key (runner_id, company_id) ties it to their
# runner's. A credential's environment is tied to the credential's runner, and
# through it to the same company.
class CreateRunnerEnvironmentsAndCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :runner_environments do |t|
      t.references :runner, null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.string :origin, null: false
      t.string :display_name
      t.boolean :ephemeral, null: false, default: false
      t.string :state, null: false
      t.string :state_reason
      t.string :os
      t.string :arch
      t.jsonb :facts, null: false, default: {}
      t.string :runner_version
      t.string :protocol_version
      t.timestamps

      t.index %i[runner_id key], unique: true
      t.index %i[id runner_id], unique: true
    end

    add_foreign_key :runner_environments, :runners, column: %i[runner_id company_id], primary_key: %i[id company_id],
                                                    on_delete: :cascade, name: "fk_runner_environments_runner_company"

    create_table :runner_credentials do |t|
      t.references :runner, null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :runner_environment, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :token_digest, null: false
      t.uuid :family_id
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.timestamps

      t.index :token_digest, unique: true
      t.index :family_id
    end

    add_foreign_key :runner_credentials, :runners, column: %i[runner_id company_id], primary_key: %i[id company_id],
                                                   on_delete: :cascade, name: "fk_runner_credentials_runner_company"
    add_foreign_key :runner_credentials, :runner_environments, column: %i[runner_environment_id runner_id],
                                                               primary_key: %i[id runner_id], on_delete: :cascade,
                                                               name: "fk_runner_credentials_environment_runner"
  end
end
