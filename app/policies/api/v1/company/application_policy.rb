# frozen_string_literal: true

module Api
  module V1
    module Company
      class ApplicationPolicy < ::ApplicationPolicy
        def current_user
          context.user
        end
      end
    end
  end
end
