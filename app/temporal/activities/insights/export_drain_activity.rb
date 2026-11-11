# frozen_string_literal: true

module Activities
  module Insights
    # Sends every session still due to Aixle Insights (::Insights::ExportRelay).
    class ExportDrainActivity < ::Activities::Base
      def run(_input = nil)
        ::Insights::ExportRelay.drain
      end
    end
  end
end
