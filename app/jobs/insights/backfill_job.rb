# frozen_string_literal: true

module Insights
  class BackfillJob < ApplicationJob
    queue_as :default

    def perform(project_id)
      project = Project.find_by(id: project_id)
      Insights::Backfill.call(project) if project&.exports_to_insights?
    end
  end
end
