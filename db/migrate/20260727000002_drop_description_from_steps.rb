# frozen_string_literal: true

# Drop steps.description, mirroring the sub_steps change in 20260727000001.
# A step (a "session" in the builder UI) carries `name` as its label and
# `instructions` as the prompt the agent actually runs on. `description` was a
# short UI summary that no view rendered outside the builder's own textarea,
# yet it shipped to the agent as its own line right above the instructions —
# duplicated intent, paid for on every run. Existing text is preserved by
# folding it into `instructions` whenever that field is blank; where both are
# filled, `instructions` wins and the description is dropped.
class DropDescriptionFromSteps < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE steps
      SET instructions = description
      WHERE description IS NOT NULL
        AND btrim(description) <> ''
        AND (instructions IS NULL OR btrim(instructions) = '')
    SQL

    remove_column :steps, :description
  end

  def down
    add_column :steps, :description, :text
  end
end
