# frozen_string_literal: true

module Web
  module Company
    class GettingStartedPolicy < ApplicationPolicy
      def show? = membership.present?
      def build_with_ai? = !read_only?
    end
  end
end
