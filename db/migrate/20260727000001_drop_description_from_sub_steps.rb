# frozen_string_literal: true

# Drop sub_steps.description. A sub-step is a checklist item: `name` is the
# label the agent and the run UI show, `instructions` is what the agent must
# actually do. `description` sat between the two with no clear boundary
# ("what this unit of work involves" vs "additional guidance"), so builder
# agents wrote the same text twice and both copies shipped in every step
# prompt. Existing text is preserved by folding it into `instructions`
# whenever that field is blank.
class DropDescriptionFromSubSteps < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE sub_steps
      SET instructions = description
      WHERE description IS NOT NULL
        AND btrim(description) <> ''
        AND (instructions IS NULL OR btrim(instructions) = '')
    SQL

    remove_column :sub_steps, :description
  end

  def down
    add_column :sub_steps, :description, :text
  end
end
