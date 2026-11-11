# frozen_string_literal: true

# docs/design/github-user-identity.md §3.1. Two independent switches per user,
# project and provider; a missing row means both are off.
class CreateActAsConsents < ActiveRecord::Migration[8.1]
  def change
    create_table :act_as_consents do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.boolean :in_own_tasks, null: false, default: false
      t.boolean :in_others_tasks, null: false, default: false
      t.timestamps

      t.index %i[user_id project_id provider], unique: true, name: "index_act_as_consents_on_user_project_provider"
    end

    add_foreign_key :act_as_consents, :projects, column: %i[project_id company_id], primary_key: %i[id company_id],
                                                 on_delete: :cascade, name: "fk_act_as_consents_project_company"
  end
end
