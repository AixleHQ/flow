# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Statistic
          class RecentActivityController < Projects::ApplicationController
            def show
              page = params.fetch(:page, 1).to_i
              per_page = params.fetch(:per_page, 20).to_i.clamp(1, 100)

              result = RecentActivityService.new(current_company, page:, per_page:, project: current_project).call

              render json: {
                activities: result[:activities].map { |a|
                  {
                    event_type: a[:event_type],
                    description: a[:description],
                    actor_name: a[:actor_name],
                    actor_type: a[:actor_type],
                    occurred_at: a[:occurred_at]&.iso8601
                  }
                },
                meta: {
                  total: result[:total],
                  page: result[:page],
                  per_page: result[:per_page]
                }
              }
            end
          end
        end
      end
    end
  end
end
