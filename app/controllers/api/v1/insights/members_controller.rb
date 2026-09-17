# frozen_string_literal: true

module Api
  module V1
    module Insights
      class MembersController < ApplicationController
        def index
          members = current_insights_project.member_users.map do |user|
            {
              id: user.id,
              email: user.email,
              name: user.name
            }
          end

          render json: { members: members }
        end
      end
    end
  end
end
