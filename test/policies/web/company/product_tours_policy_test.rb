# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    class ProductToursPolicyTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
      end

      def policy_for(user)
        ProductToursPolicy.new(BaseContext.new(user, {}, company: @company), :product_tours)
      end

      test "every member records their own tour, viewers included; an outsider does not" do
        %i[admin employee viewer].each do |role|
          assert policy_for(create(:user, role, company: @company)).update?, role
        end
        assert_not policy_for(create(:user, :admin, company: create(:company))).update?
      end
    end
  end
end
