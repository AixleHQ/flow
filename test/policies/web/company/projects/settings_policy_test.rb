# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      class SettingsPolicyTest < ActiveSupport::TestCase
        setup do
          @company = create(:company)
          @owner = create(:user, :employee, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @owner)
          @admin = create(:user, :admin, :onboarding_completed, company: @company)
          @collaborator = create(:user, :employee, :onboarding_completed, company: @company)
          @project.add_collaborator(@collaborator)
          @viewer = create(:user, :viewer, :onboarding_completed, company: @company)
          @project.add_collaborator(@viewer)
        end

        test "manage_insights_sharing? permits owner and company admin" do
          assert policy_for(@owner).manage_insights_sharing?
          assert policy_for(@admin).manage_insights_sharing?
        end

        test "manage_insights_sharing? forbids collaborator and viewer" do
          assert_not policy_for(@collaborator).manage_insights_sharing?
          assert_not policy_for(@viewer).manage_insights_sharing?
        end

        test "regenerate_insights_connection_token? matches manage_insights_sharing?" do
          assert policy_for(@owner).regenerate_insights_connection_token?
          assert_not policy_for(@collaborator).regenerate_insights_connection_token?
        end

        private

        def policy_for(user)
          Web::Company::Projects::SettingsPolicy.new(
            ProjectContext.new(user, {}, project: @project),
            @project
          )
        end
      end
    end
  end
end
