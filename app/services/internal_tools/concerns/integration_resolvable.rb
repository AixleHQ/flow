# frozen_string_literal: true

module InternalTools
  module Concerns
    module IntegrationResolvable
      extend ActiveSupport::Concern

      class_methods do
        def resolves_integration_for(provider)
          define_method(:"#{provider}_integration") { resolve_integration(provider) }
        end
      end

      private

      def resolve_integration(provider)
        return if project.nil?
        scope = Integration.visible_for_project(project).active.where(provider: provider)
        context = workflow_run&.shared_context.to_h[provider.to_s] || {}
        if (id = context["integration_id"]).present? && (found = scope.find_by(id: id))
          return found
        end
        scope.order(Arel.sql("project_id IS NULL"), :id).first
      end
    end
  end
end
