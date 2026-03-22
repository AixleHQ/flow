# frozen_string_literal: true

module Api
  module V1
    module Company
      module Statistic
        class TopAgentsController < Company::ApplicationController
          def show
            limit = params.fetch(:limit, 10).to_i.clamp(1, 50)
            agents = TopAgentsBySessionsService.new(current_company, limit: limit).call
            render body: agents.map(&:to_h).to_json, content_type: :json
          end
        end
      end
    end
  end
end
