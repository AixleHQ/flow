# frozen_string_literal: true

module InternalTools
  module Concerns
    module YoutrackContext
      def youtrack_context = workflow_run&.shared_context.to_h["youtrack"] || {}

      def youtrack_integration
        return if project.nil?
        scope = Integration.active.where(provider: :youtrack, company_id: project.company_id)
        if (id = youtrack_context["integration_id"]).present?
          return scope.find_by(id: id)
        end
        scope.where("project_id = :pid OR project_id IS NULL", pid: project.id)
          .order(Arel.sql("project_id IS NULL"), :id).first
      end

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
