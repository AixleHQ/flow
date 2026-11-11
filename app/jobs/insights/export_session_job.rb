# frozen_string_literal: true

module Insights
  # The inline send of a session to Insights, right after its records were committed.
  class ExportSessionJob < ApplicationJob
    queue_as :default

    def perform(export_id)
      Insights::Export.deliver(export_id)
    end
  end
end
