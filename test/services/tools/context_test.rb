# frozen_string_literal: true

require "test_helper"

class Tools::ContextTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
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

  test "batches the integration lookup into one memoized query" do
    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)
    ctx = Tools::Context.new(project: @project, company: @company)

    assert_queries_count(1) { ctx.connected?(:slack) }
    assert_no_queries do
      ctx.connected?(:coder)
      ctx.connected?(:github)
      ctx.connected?(:slack)
    end
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
