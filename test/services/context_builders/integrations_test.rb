# frozen_string_literal: true

require "test_helper"

class ContextBuilders::IntegrationsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, mode: "interactive")
  end

  test "not applicable to a session with no integrations" do
    assert_not ContextBuilders::Integrations.new(@session).applicable?
  end

  test "lists the session's integrations by id, name and provider, with the Coder host and template" do
    coder = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user, name: "Coder (alice)")
    coder.update!(settings: coder.settings.merge("default_template" => "tpl"))
    @session.integrations << coder

    builder = ContextBuilders::Integrations.new(@session.reload)
    section = builder.build.first

    assert builder.applicable?
    assert_equal "available-integrations", section.tag
    assert_includes section.content, "| #{coder.id} | Coder (alice) | coder | coder.example.com, template tpl |"
    assert_includes section.content, "Pass the integration **ID** as `integration_id`"
  end

  test "repository-derived integrations are not listed: repositories keep their own table" do
    github = create(:integration, :github_pat, :active, company: @company, project: @project, connected_by: @user)
    @session.integrations << github

    assert_not ContextBuilders::Integrations.new(@session.reload).applicable?
  end

  test "never prints credentials" do
    coder = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    @session.integrations << coder

    content = ContextBuilders::Integrations.new(@session.reload).build.first.content

    assert_not_includes content, coder.credentials_data["session_token"]
    assert_not_includes content, "https://"
  end

  test "a name with a pipe does not break the table" do
    coder = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user, name: "a|b")
    @session.integrations << coder

    assert_includes ContextBuilders::Integrations.new(@session.reload).build.first.content, "a\\|b"
  end
end
