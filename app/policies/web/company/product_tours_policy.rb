# frozen_string_literal: true

module Web
  module Company
    class ProductToursPolicy < ApplicationPolicy
      def update? = membership.present?
    end
  end
end
