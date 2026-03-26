# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Statistic
          class AnalyticsPolicy < Api::V1::Company::ApplicationPolicy
            def show?
              project_accessible?
            end

            def agent_activity?
              project_accessible?
            end

            def session_source_breakdown?
              project_accessible?
            end

            def session_duration_distribution?
              project_accessible?
            end

            def cost_token_usage?
              project_accessible?
            end

            def filter_options?
              project_accessible?
            end

            private

            def project
              context.project
            end

            def project_accessible?
              return false unless project

              project.accessible_by?(current_user)
            end
          end
        end
      end
    end
  end
end
