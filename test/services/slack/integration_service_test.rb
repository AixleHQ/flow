# frozen_string_literal: true

require "test_helper"

module Slack
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.company
      @project = create(:project, owner: @user, company: @company)
    end

    def service
      Slack::IntegrationService.new(company: @company, connected_by: @user, project: @project)
    end

    test "create provisions an active integration and a Slack webhook endpoint" do
      integration = service.create(workspace_name: "Acme HQ", signing_secret: "shh")

      assert integration.persisted?
      assert integration.active?
      assert_equal "Acme HQ", integration.name
      assert_equal "shh", integration.credentials_data["signing_secret"]

      endpoint = WebhookEndpoint.find(integration.settings["webhook_endpoint_id"])
      assert endpoint.slack?
      assert_equal "slack_v0", endpoint.verification_strategy
      assert_equal "shh", endpoint.secret
      assert_equal @project.id, endpoint.project_id
      assert_includes integration.settings["request_url"], "/webhooks/in/#{endpoint.slug}"
    end

    test "create without a signing secret returns an error integration and no endpoint" do
      assert_no_difference -> { WebhookEndpoint.count } do
        integration = service.create(workspace_name: "Acme", signing_secret: "")

        assert integration.persisted?
        assert integration.error?
        assert_equal "Signing secret is required", integration.settings["error"]
      end
    end
  end
end
