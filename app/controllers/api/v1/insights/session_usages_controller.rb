# frozen_string_literal: true

module Api
  module V1
    module Insights
      class SessionUsagesController < ApplicationController
        def index
          result = ::Insights::SessionUsagesQuery.call(
            project: current_insights_project,
            since: params[:since],
            after_id: params[:after_id],
            limit: params[:limit]
          )

          render json: {
            session_usages: result[:session_usages],
            next_cursor: result[:next_cursor]
          }
        end
      end
    end
  end
end
