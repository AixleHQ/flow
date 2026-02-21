# frozen_string_literal: true

module Activities
  module Asset
    class CleanupDismissedActivity < Base
      GRACE_PERIOD = 7.days

      def run(_input = nil)
        assets = ::Asset.dismissed
                      .where.not(reviewed_at: nil)
                      .where(reviewed_at: ...GRACE_PERIOD.ago)

        count = 0
        freed_bytes = 0

        assets.find_each do |asset|
          bytes = asset.versions.sum(:file_size).to_i
          asset.versions.each(&:destroy!)
          asset.destroy!
          freed_bytes += bytes
          count += 1
        rescue StandardError => e
          log(:warn, "Failed to clean asset #{asset.id}: #{e.message}")
        end

        log(:info, "Cleaned #{count} dismissed assets, freed ~#{freed_bytes / 1024}KB")
        { cleaned_count: count, freed_bytes: freed_bytes }
      end
    end
  end
end
