# frozen_string_literal: true

module InternalTools
  module Concerns
    module YoutrackContext
      include IntegrationResolvable
      resolves_integration_for :youtrack

      def youtrack_context = workflow_run&.shared_context.to_h["youtrack"] || {}

      def with_youtrack
        return error("This tool needs a project") if project.nil?
        integration = youtrack_integration
        return error("YouTrack is not connected for this project") unless integration
        yield Youtrack::Client.new(integration), integration
      rescue Youtrack::Client::Error => e
        error(e.message)
      end

      def json_success(value) = success(JSON.pretty_generate(value))
    end
  end
end
