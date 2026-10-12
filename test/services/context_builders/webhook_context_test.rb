# frozen_string_literal: true

require "test_helper"

class ContextBuilders::WebhookContextTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @user = create(:user, :admin, company: company)
    @project = create(:project, company: company, owner: @user)
    workflow = create(:workflow, scope: @project)
    @workflow_run = create(:workflow_run, :running, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, :running, workflow_run: @workflow_run, step: create(:step, workflow: workflow))
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)
  end

  test "a run a webhook started sends the agent to the file that holds the request body" do
    @workflow_run.update!(shared_context: { "webhook" => { "payload" => {
      "column" => "Backlog", "title" => "Security Hub — 20 Critical", "description" => "## Totals\n375 findings"
    } } })

    content = ContextBuilders::WebhookContext.new(@session).build.sole.content

    assert_includes content, "`/workspace/assets/webhook-payload.json`"
    assert_not_includes content, "Security Hub — 20 Critical"
  end

  test "a request with no JSON body says so instead of pointing at a file that is not there" do
    @workflow_run.update!(shared_context: { "webhook" => { "payload" => {} } })

    content = ContextBuilders::WebhookContext.new(@session).build.sole.content

    assert_includes content, "no JSON body"
    assert_not_includes content, "webhook-payload.json"
  end

  test "it stays out of runs no webhook started" do
    @workflow_run.update!(shared_context: { "tracker" => { "handle" => "boards" } })

    refute_predicate ContextBuilders::WebhookContext.new(@session), :applicable?
  end
end
