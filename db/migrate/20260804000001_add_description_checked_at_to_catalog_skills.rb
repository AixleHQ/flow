# frozen_string_literal: true

# The description backfill needs to remember that it ASKED, not just whether it
# succeeded. A SKILL.md legitimately without a `description` key yields nil, so
# `description IS NULL` alone cannot distinguish "never looked" from "looked, nothing
# there" — and the queue ordered by ranking re-offered the same unanswerable rows
# first on every run, spending the whole per-run budget on them forever.
class AddDescriptionCheckedAtToCatalogSkills < ActiveRecord::Migration[8.0]
  def change
    add_column :catalog_skills, :description_checked_at, :datetime

    # The queue is exactly `description IS NULL ORDER BY description_checked_at`, so
    # the index is partial: described rows are the majority once this works and have
    # no business in it.
    add_index :catalog_skills, :description_checked_at,
              where: "description IS NULL",
              name: "index_catalog_skills_on_backfill_queue"
  end
end
