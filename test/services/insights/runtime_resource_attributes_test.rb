# frozen_string_literal: true

require "test_helper"

module Insights
  class RuntimeResourceAttributesTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, user: @user, project: @project,
                                           agent_type: "claude_code", route_token: "route-token")
    end

    test "returns only allowlisted business metadata for an active project integration" do
      integration = create(:integration, :insights, :active, company: @company,
                                                               project: @project, connected_by: @user)

      attributes = RuntimeResourceAttributes.for(@session)

      assert_equal({ "user_email" => @user.email, "project_name" => @project.name, "proxy_enabled" => "true" },
                   attributes)
      refute_includes attributes.values, integration.insights_ingest_token
    end

    test "is empty without an active integration" do
      create(:integration, :insights, company: @company, project: @project, connected_by: @user)

      assert_empty RuntimeResourceAttributes.for(@session)
    end

    test "does not use another project's active integration" do
      other_project = create(:project, company: @company, owner: @user)
      create(:integration, :insights, :active, company: @company,
                                               project: other_project, connected_by: @user)

      assert_empty RuntimeResourceAttributes.for(@session)
    end

    test "is empty for runtimes outside the supported allowlist" do
      create(:integration, :insights, :active, company: @company,
                                               project: @project, connected_by: @user)

      %w[grok cursor_cli antigravity_cli].each do |agent_type|
        @session.agent_type = agent_type

        assert_empty RuntimeResourceAttributes.for(@session), agent_type
      end
    end

    test "is empty for a session without a project" do
      @session.project = nil

      assert_empty RuntimeResourceAttributes.for(@session)
      assert_empty RuntimeResourceAttributes.for(nil)
    end
  end
end
