# frozen_string_literal: true

module Web
  module Company
    class ApplicationPolicy < ::ApplicationPolicy
      private

      def current_user
        context.user
      end
    end
  end
end
