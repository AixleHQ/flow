# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    class RunnersPolicyTest < ActiveSupport::TestCase
      WRITES = %i[create? update? destroy? disable? enable? revoke?].freeze

      setup do
        @company = create(:company)
        @admin = create(:user, :admin, company: @company)
      end

      # The policy authorizes the action only, so its record is the `:runners`
      # symbol. Which runner a request may touch is the controller's lookup.
      def policy_for(user)
        RunnersPolicy.new(BaseContext.new(user, {}, company: @company), :runners)
      end

      test "every active member lists and views company runners; an outsider does not" do
        [ @admin, create(:user, :employee, company: @company),
          create(:user, :viewer, company: @company, email: "client-#{SecureRandom.hex(3)}@external.com") ].each do |user|
          assert policy_for(user).index?
          assert policy_for(user).show?
        end
        assert_not policy_for(create(:user, :admin, company: create(:company))).index?
      end

      test "only a company admin manages company runners" do
        employee = create(:user, :employee, company: @company)

        WRITES.each do |query|
          assert policy_for(@admin).public_send(query), query
          assert_not policy_for(employee).public_send(query), query
        end
      end
    end
  end
end
