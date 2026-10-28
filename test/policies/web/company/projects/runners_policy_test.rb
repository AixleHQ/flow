# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      class RunnersPolicyTest < ActiveSupport::TestCase
        WRITES = %i[create? update? destroy? disable? enable? revoke?].freeze

        setup do
          @company = create(:company)
          @owner = create(:user, :employee, company: @company)
          @project = create(:project, company: @company, owner: @owner)
          @admin = create(:user, :admin, company: @company)
          @own = create(:runner, company: @company, project: @project, created_by: @owner)
          @company_runner = create(:runner, company: @company, created_by: @admin)
        end

        def policy_for(user, record = :runners)
          RunnersPolicy.new(ProjectContext.new(user, {}, project: @project), record)
        end

        def collaborator_with(*traits, **attrs)
          create(:user, *traits, company: @company, **attrs).tap { |u| @project.add_collaborator(u) }
        end

        test "anyone the project is accessible to lists and views its runners and the company's" do
          viewer = collaborator_with(:viewer, email: "client-#{SecureRandom.hex(3)}@external.com")

          [ @owner, @admin, collaborator_with(:employee), viewer ].each do |user|
            assert policy_for(user).index?
            assert policy_for(user, @company_runner).show?
          end
          assert_not policy_for(create(:user, :employee, company: @company)).index?
        end

        test "a company admin and the project owner manage the project's own runners" do
          [ @admin, @owner ].each do |user|
            WRITES.each do |query|
              assert policy_for(user).public_send(query), query
              assert policy_for(user, @own).public_send(query), query
            end
          end
        end

        test "a collaborator and a viewer manage nothing" do
          viewer = collaborator_with(:viewer, email: "client-#{SecureRandom.hex(3)}@external.com")

          [ collaborator_with(:employee), viewer ].each do |user|
            WRITES.each { |query| assert_not policy_for(user, @own).public_send(query), query }
          end
        end

        test "nobody manages a company runner from a project page" do
          [ @admin, @owner ].each do |user|
            WRITES.each { |query| assert_not policy_for(user, @company_runner).public_send(query), query }
          end
        end
      end
    end
  end
end
