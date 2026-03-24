# frozen_string_literal: true

class AddWebhookSecretToRepositories < ActiveRecord::Migration[8.0]
  def change
    add_column :repositories, :webhook_secret, :string
    add_index :repositories, :webhook_secret, unique: true
  end
end
