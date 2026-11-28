# frozen_string_literal: true

require "test_helper"

class Tools::ContextTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
  end

  test "connected? sees active project-scoped and company-wide integrations" do
    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)
    create(:integration, company: @company, project: nil, provider: :coder,
                         status: :active, connected_by: @user)

    ctx = Tools::Context.new(project: @project, company: @company)

    assert ctx.connected?(:slack)
    assert ctx.connected?("coder")
    assert_not ctx.connected?(:github)
  end

  test "inactive integrations and other projects' integrations do not count" do
    other_project = create(:project, owner: @user, company: @company)
    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :inactive, connected_by: @user)
    create(:integration, company: @company, project: other_project, provider: :coder,
                         status: :active, connected_by: @user)

    ctx = Tools::Context.new(project: @project, company: @company)

    assert_not ctx.connected?(:slack)
    assert_not ctx.connected?(:coder)
  end

  test "without a project only company-wide integrations count" do
    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)
    create(:integration, company: @company, project: nil, provider: :github,
                         status: :active, connected_by: @user)

    ctx = Tools::Context.new(project: nil, company: @company)

    assert_not ctx.connected?(:slack)
    assert ctx.connected?(:github)
  end

  test "batches the integration lookup into one memoized query, plus one for trackers" do
    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)
    ctx = Tools::Context.new(project: @project, company: @company)

    assert_queries_count(2) { ctx.connected?(:slack) }
    assert_no_queries do
      ctx.connected?(:coder)
      ctx.connected?(:github)
      ctx.connected?(:slack)
    end
  end

  test "a code-host connection with pull-request tools adds the capability, others do not" do
    create(:integration, :gitlab, :active, company: @company, project: @project, connected_by: @user)

    assert Tools::Context.new(project: @project, company: @company).connected?(PullRequests::CAPABILITY)

    other = create(:project, owner: @user, company: @company)
    create(:integration, :coder, :active, company: @company, project: other, connected_by: @user)
    assert_not Tools::Context.new(project: other, company: @company).connected?(PullRequests::CAPABILITY)

    github = create(:project, owner: @user, company: @company)
    create(:integration, :github, :active, company: @company, project: github, connected_by: @user)
    assert Tools::Context.new(project: github, company: @company).connected?(PullRequests::CAPABILITY)
  end

  test "with a session, only the providers of the session's own integrations count" do
    slack = create(:integration, company: @company, project: @project, provider: :slack, status: :active, connected_by: @user)
    create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.integrations << slack

    ctx = Tools::Context.for_session(session.reload)

    assert ctx.connected?(:slack)
    assert ctx.connected?(Chat::CAPABILITY)
    assert_not ctx.connected?(:coder)
  end

  test "a session with no integrations has no integration providers, however much the project has connected" do
    create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    ctx = Tools::Context.for_session(session)

    assert_not ctx.connected?(:coder)
    assert Tools::Context.for_project(@project).connected?(:coder)
  end

  test "a repository's integration puts the pull-request capability in a session's set" do
    github = create(:integration, :github_pat, :active, company: @company, project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.integrations << github

    assert Tools::Context.for_session(session.reload).connected?(PullRequests::CAPABILITY)
  end

  test "an inactive integration in a session's set does not count" do
    coder = create(:integration, :coder, status: :error, company: @company, project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.integrations << coder

    assert_not Tools::Context.for_session(session.reload).connected?(:coder)
  end

  test "attach_message names the attach remedy for a session whose project has the provider connected" do
    create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    message = Tools::Context.for_session(session).attach_message(:coder)

    assert_equal "The coder integration is not attached to this session. " \
                 "Attach it to the workflow, the step or the session.", message
  end

  test "attach_message is nil without a session, when attached, or when the project has nothing connected" do
    coder = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    assert_nil Tools::Context.for_project(@project).attach_message(:coder)
    assert_nil Tools::Context.for_session(session).attach_message(:slack)

    session.integrations << coder
    assert_nil Tools::Context.for_session(session.reload).attach_message(:coder)
  end

  test "no company yields an empty provider set without querying" do
    ctx = Tools::Context.new(project: nil, company: nil)

    assert_no_queries { assert_not ctx.connected?(:slack) }
  end

  test "for_session carries session mode and type" do
    session = create(:terminal_session, user: @user, project: @project,
                     session_type: "workflow_step", mode: "non_interactive",
                     initial_prompt: "run the step")

    ctx = Tools::Context.for_session(session)

    assert_equal @project, ctx.project
    assert_equal @company, ctx.company
    assert_equal "workflow_step", ctx.session_type
    assert_equal "non_interactive", ctx.mode
  end
end
