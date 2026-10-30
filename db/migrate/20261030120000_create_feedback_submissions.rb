# frozen_string_literal: true

class CreateFeedbackSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :feedback_submissions do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, index: false, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.text :message, null: false
      t.string :page_url
      t.string :app_version
      t.datetime :slack_delivered_at
      t.datetime :board_delivered_at
      t.timestamps

      t.index %i[user_id created_at]
    end

    create_table :feedback_attachments do |t|
      t.references :feedback_submission, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.jsonb :file_data
      t.timestamps
    end
  end
end
