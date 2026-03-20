# frozen_string_literal: true

module Api
  module V1
    module Company
      class OverviewPolicy < ApplicationPolicy
        def show?
          true # all authenticated company members can view the overview
        end
      end
    end
  end
end
