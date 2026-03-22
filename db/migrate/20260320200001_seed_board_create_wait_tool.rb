# frozen_string_literal: true

class SeedBoardCreateWaitTool < ActiveRecord::Migration[7.2]
  def up
    # No-op: data seeding moved to db/seeds/platform_tools.rb.
    # The deploy workflow runs `platform_tools:seed` after `db:migrate`
    # to register board tools idempotently.
  end

  def down
    # no-op
  end
end
