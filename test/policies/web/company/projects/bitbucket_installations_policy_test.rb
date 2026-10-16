# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      class BitbucketInstallationsPolicyTest < ActiveSupport::TestCase
        setup do
          @company = create(:company)
          @owner = create(:user, :employee, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @owner)
          @viewer = create(:user, :viewer, company: @company, email: "client@external.com")
          @project.add_collaborator(@viewer)
          @outsider = create(:user, :employee, :onboarding_completed, company: create(:company))
        end

        def policy(user) = BitbucketInstallationsPolicy.new(ProjectContext.new(user, {}, project: @project), nil)

        test "connecting a bound workspace is for those who may write to the project" do
          assert policy(@owner).create?
          assert_not policy(@viewer).create?
          assert_not policy(@outsider).create?
        end
      end
    end
  end
end
