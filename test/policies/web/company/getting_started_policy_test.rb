# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    class GettingStartedPolicyTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
      end

      def policy_for(user)
        GettingStartedPolicy.new(BaseContext.new(user, {}, company: @company), :getting_started)
      end

      test "every member sees getting started; only those who can write build with AI" do
        %i[admin employee viewer].each do |role|
          assert policy_for(create(:user, role, company: @company)).show?, role
        end
        assert policy_for(create(:user, :employee, company: @company)).build_with_ai?
        assert_not policy_for(create(:user, :viewer, company: @company)).build_with_ai?
      end

      test "an outsider gets neither" do
        policy = policy_for(create(:user, :admin, company: create(:company)))

        assert_not policy.show?
        assert_not policy.build_with_ai?
      end
    end
  end
end
