# frozen_string_literal: true

module Web
  module Company
    class FeedbackPolicy < ApplicationPolicy
      def create? = membership.present?
    end
  end
end
