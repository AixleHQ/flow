# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    class RunnersPolicyTest < ActiveSupport::TestCase
      WRITES = %i[create? update? destroy? disable? enable? revoke?].freeze

      setup do
        @company = create(:company)
        @admin = create(:user, :admin, company: @company)
        @runner = create(:runner, company: @company, created_by: @admin)
      end

      def policy_for(user, record = :runners)
        RunnersPolicy.new(BaseContext.new(user, {}, company: @company), record)
      end

      test "every active member lists and views company runners; an outsider does not" do
        [ @admin, create(:user, :employee, company: @company),
          create(:user, :viewer, company: @company, email: "client-#{SecureRandom.hex(3)}@external.com") ].each do |user|
          assert policy_for(user).index?
          assert policy_for(user, @runner).show?
        end
        assert_not policy_for(create(:user, :admin, company: create(:company))).index?
      end

      test "only a company admin manages company runners" do
        employee = create(:user, :employee, company: @company)

        WRITES.each do |query|
          assert policy_for(@admin).public_send(query), query
          assert policy_for(@admin, @runner).public_send(query), query
          assert_not policy_for(employee, @runner).public_send(query), query
        end
      end

      test "a project's runner is not managed as a company runner" do
        project_runner = create(:runner, :project_runner, company: @company, created_by: @admin)

        WRITES.each { |query| assert_not policy_for(@admin, project_runner).public_send(query), query }
      end
    end
  end
end
