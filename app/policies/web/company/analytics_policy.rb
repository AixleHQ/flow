# frozen_string_literal: true

module Web
  module Company
    class AnalyticsPolicy < ApplicationPolicy
      def index? = current_user.admin?
    end
  end
end
