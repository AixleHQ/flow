# frozen_string_literal: true

module Web
  module Company
    class AnalyticsPolicy < ApplicationPolicy
      def index? = admin?
    end
  end
end
