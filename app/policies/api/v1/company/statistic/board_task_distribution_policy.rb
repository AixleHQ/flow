# frozen_string_literal: true

module Api
  module V1
    module Company
      module Statistic
        class BoardTaskDistributionPolicy < Company::ApplicationPolicy
          def show?
            true # all authenticated company members can view stats
          end
        end
      end
    end
  end
end
