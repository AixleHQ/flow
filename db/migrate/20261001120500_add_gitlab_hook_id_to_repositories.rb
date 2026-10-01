# frozen_string_literal: true

class AddGitlabHookIdToRepositories < ActiveRecord::Migration[8.1]
  def change
    add_column :repositories, :gitlab_hook_id, :bigint
  end
end
