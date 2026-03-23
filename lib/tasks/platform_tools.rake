# frozen_string_literal: true

namespace :platform_tools do
  desc "Seed platform tools into the database (idempotent — safe to re-run)"
  task seed: :environment do
    require Rails.root.join("db/seeds/platform_tools")
    Seeds::PlatformTools.seed!
  end
end
