# frozen_string_literal: true

class RenameDefaultBranchToSourceBranch < ActiveRecord::Migration[8.0]
  def change
    rename_column :repositories, :default_branch, :source_branch
  end
end
