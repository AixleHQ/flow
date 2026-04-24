# frozen_string_literal: true

module Web
  module Company
    class AnalyticsPolicy < ApplicationPolicy
      def index? = true
    end
  end
end
