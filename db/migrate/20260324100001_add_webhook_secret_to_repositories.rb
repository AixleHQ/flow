# frozen_string_literal: true

class AddWebhookSecretToRepositories < ActiveRecord::Migration[8.0]
  def change
    add_column :repositories, :webhook_secret, :string unless column_exists?(:repositories, :webhook_secret)
    add_index :repositories, :webhook_secret, unique: true unless index_exists?(:repositories, :webhook_secret)
  end
end
