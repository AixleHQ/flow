# frozen_string_literal: true

module Activities
  module Trackers
    # Daily, from Workflows::TrackerPersonalDataWorkflow: reports the Atlassian
    # account ids Aixle keeps once their cycle comes round, and drops webhook
    # deliveries past a week — they are an inbox, and carry actors' names.
    class ReportPersonalDataActivity < ::Activities::Base
      DELIVERY_RETENTION = 7.days

      def run(_input = nil)
        purged = TrackerDelivery.where(created_at: ...DELIVERY_RETENTION.ago).delete_all
        counts = ::Trackers::Jira::PersonalDataReporter.new.run
        log(:info, "tracker personal data: #{counts} purged_deliveries=#{purged}")
        counts.merge(purged_deliveries: purged)
      end
    end
  end
end
