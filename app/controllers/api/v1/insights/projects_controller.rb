# frozen_string_literal: true

module Api
  module V1
    module Insights
      class ProjectsController < ApplicationController
        def show
          project = current_insights_project
          render json: {
            id: project.id,
            name: project.name,
            slug: project.slug,
            company_id: project.company_id,
            share_usage_with_insights: project.share_usage_with_insights?
          }
        end
      end
    end
  end
end
