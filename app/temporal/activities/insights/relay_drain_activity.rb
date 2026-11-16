# frozen_string_literal: true

module Activities
  module Insights
    # Sends every connection's due OTLP batches to Aixle Insights (::Insights::Relay.drain).
    class RelayDrainActivity < ::Activities::Base
      def run(_input = nil)
        ::Insights::Relay.drain.transform_keys(&:to_s)
      end
    end
  end
end
