# frozen_string_literal: true

module Api
  module V1
    module Company
      module Statistic
        class OverviewPolicy < Company::ApplicationPolicy
          def show?
            true # all authenticated company members can view the overview
          end
        end
      end
    end
  end
end
