# frozen_string_literal: true

require "test_helper"

# Integrations attached to workflows, steps and sessions (docs/design/session-integrations.md §4).
class SessionIntegrationsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @step = create(:step, workflow: @workflow)
    @coder = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
  end

  test "only Coder, Slack, Teams and Azure DevOps can be attached" do
    assert_equal %w[coder slack teams azure_devops], Integration::ATTACHABLE_PROVIDERS
    assert_equal [ @coder ], Integration.attachable.where(company: @company).to_a
  end

  test "a workflow and a step keep their integration lists as resource links" do
    @workflow.merge_config!("base_integration_ids" => [ @coder.id ])
    @step.update!(integration_ids: [ @coder.id ])

    assert_equal [ @coder.id ], @workflow.reload.base_integration_ids
    assert_equal [ @coder.id ], @step.reload.integration_ids
    assert_equal [ @coder.id ], @workflow.linked_config["base_integration_ids"]
  end

  test "a company-wide integration of the project's company is attachable" do
    wide = create(:integration, :coder, :active, company: @company, connected_by: @user)

    @workflow.merge_config!("base_integration_ids" => [ wide.id ])

    assert_equal [ wide.id ], @workflow.reload.base_integration_ids
  end

  test "an integration of another project or another company is refused on a workflow and a step" do
    other_project = create(:project, company: @company, owner: @user)
    elsewhere = create(:integration, :coder, :active, company: create(:company))
    sibling = create(:integration, :coder, :active, company: @company, project: other_project, connected_by: @user)

    [ elsewhere, sibling ].each do |integration|
      assert_raises(ActiveRecord::RecordInvalid) { @workflow.merge_config!("base_integration_ids" => [ integration.id ]) }
      assert_raises(ActiveRecord::RecordInvalid) { @step.update!(integration_ids: [ integration.id ]) }
    end
  end

  test "a provider that is reached some other way is refused" do
    github = create(:integration, :github_pat, :active, company: @company, project: @project)

    error = assert_raises(ActiveRecord::RecordInvalid) { @step.update!(integration_ids: [ github.id ]) }
    assert_match(/cannot be attached/, error.message)
    assert_raises(ActiveRecord::RecordInvalid) { @workflow.merge_config!("base_integration_ids" => [ github.id ]) }
  end

  test "a system workflow holds no integrations" do
    system = create(:workflow, :system)

    assert_raises(ActiveRecord::RecordInvalid) { system.merge_config!("base_integration_ids" => [ @coder.id ]) }
  end

  test "a stale id of a deleted integration does not keep the workflow from saving" do
    @workflow.merge_config!("base_integration_ids" => [ @coder.id ])
    @coder.destroy!

    assert_empty @workflow.reload.base_integration_ids
    assert @workflow.update(description: "still editable")
  end

  test "disconnecting an integration drops its links and its session rows" do
    @step.update!(integration_ids: [ @coder.id ])
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.integrations << @coder

    @coder.destroy!

    assert_empty @step.reload.integration_ids
    assert_empty session.reload.integrations
  end

  test "a session is created with the integrations it names, and refuses a foreign or unattachable one" do
    session = build(:terminal_session, :agent_session, user: @user, project: @project)
    session.integrations = [ @coder ]
    assert session.valid?

    foreign = create(:integration, :coder, :active, company: create(:company))
    session.integrations = [ foreign ]
    assert_not session.valid?

    github = create(:integration, :github_pat, :active, company: @company, project: @project)
    session.integrations = [ github ]
    assert_not session.valid?
    assert_match(/cannot be attached/, session.errors[:integrations].join)
  end
end
