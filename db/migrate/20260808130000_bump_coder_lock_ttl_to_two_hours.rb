# frozen_string_literal: true

# The Coder workspace lock TTL default moved from 60 to 120 minutes: an hour is
# shorter than a real terminal session, so the lock expired underneath a session
# that was still using the workspace and another session could claim it.
#
# The code default (Coder::LockService#ttl_minutes) only applies when the
# integration has no explicit value, and every integration connected through the
# UI has one — the form requires the field and shipped 60 as its default. This
# migration moves those rows to 120 so existing integrations get the new
# behaviour without an operator editing each one.
#
# Only rows still sitting at the old default are touched. Anything else is an
# operator's deliberate choice and is left alone.
class BumpCoderLockTtlToTwoHours < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Bumping Coder lock TTL from 60 to 120 minutes" do
      execute(<<~SQL.squish)
        UPDATE integrations
        SET settings = jsonb_set(settings, '{lock_ttl_minutes}', '120'::jsonb),
            updated_at = NOW()
        WHERE provider = 'coder'
          AND settings->>'lock_ttl_minutes' = '60'
      SQL
    end
  end

  # Not reversible: after the update, a row at 120 could be one this migration
  # moved or one an operator chose. Rolling every 120 back to 60 would clobber
  # the latter.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
