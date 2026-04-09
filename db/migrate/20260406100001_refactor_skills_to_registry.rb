# frozen_string_literal: true

class RefactorSkillsToRegistry < ActiveRecord::Migration[8.1]
  def up
    # Remove all internal skills — they're being replaced by registry-based skills
    execute "DELETE FROM session_skills WHERE skill_id IN (SELECT id FROM skills WHERE kind = 'internal')"
    execute "DELETE FROM skills WHERE kind = 'internal'"

    # Add registry fields
    add_column :skills, :package, :string    # e.g. "mantinedev/skills@mantine-form"
    add_column :skills, :source, :string     # e.g. "mantinedev/skills"
    add_column :skills, :source_url, :string # e.g. "https://github.com/mantinedev/skills"
    add_column :skills, :install_count, :integer, default: 0

    # Remove kind column — all skills are now registry-based
    remove_index :skills, :kind
    remove_column :skills, :kind

    add_index :skills, :package
  end

  def down
    remove_index :skills, :package, if_exists: true

    remove_column :skills, :package
    remove_column :skills, :source
    remove_column :skills, :source_url
    remove_column :skills, :install_count

    add_column :skills, :kind, :string, null: false, default: "custom"
    add_index :skills, :kind
  end
end
