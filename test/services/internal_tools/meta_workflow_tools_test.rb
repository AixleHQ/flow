# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaWorkflowToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    # Create a "builder" workflow context (simulating Aixle Builder running)
    builder_workflow = create(:workflow, scope: @project)
    builder_step = create(:step, workflow: builder_workflow)
    @workflow_run = create(:workflow_run, workflow: builder_workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: builder_step)

    step_run = @step_run
    project = @project
    workflow_run = @workflow_run
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }
  end

  # ── meta_create_workflow ──

  test "meta_create_workflow creates workflow in target project" do
    result = InternalTools::MetaCreateWorkflow.new(
      params: { name: "Test Workflow", description: "A test" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Test Workflow", data["name"]
    assert_equal "Project", data["scope_type"]
    assert_equal @project.id, data["scope_id"]

    # Verify stored in shared_context
    @workflow_run.reload
    assert_equal data["id"], @workflow_run.shared_context["target_workflow_id"]
  end

  test "meta_create_workflow fails with missing name" do
    result = InternalTools::MetaCreateWorkflow.new(
      params: {},
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Failed to create workflow"
  end

  test "meta_create_workflow fails with duplicate name" do
    create(:workflow, scope: @project, name: "Existing")

    result = InternalTools::MetaCreateWorkflow.new(
      params: { name: "Existing" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "already exists"
  end

  # ── meta_create_agent ──

  test "meta_create_agent creates agent in project scope" do
    result = InternalTools::MetaCreateAgent.new(
      params: { name: "test_agent", title: "Test Agent", persona: "You are a test agent." },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Test Agent", data["title"]
    assert_equal "Project", data["scope_type"]
  end

  test "meta_create_agent fails without title" do
    result = InternalTools::MetaCreateAgent.new(
      params: { persona: "Some persona" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
  end

  # ── meta_create_step ──

  test "meta_create_step creates step on target workflow" do
    wf = create(:workflow, scope: @project, name: "Target WF")
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaCreateStep.new(
      params: { name: "Step 1", instructions: "Do something" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Step 1", data["name"]
    assert_equal wf.id, data["workflow_id"]
    assert_equal 1, data["position"]
  end

  test "meta_create_step auto-assigns position" do
    wf = create(:workflow, scope: @project)
    create(:step, workflow: wf, name: "Existing", position: 1)
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaCreateStep.new(
      params: { name: "Step 2" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal 2, data["position"]
  end

  test "meta_create_step fails without target workflow" do
    result = InternalTools::MetaCreateStep.new(
      params: { name: "Orphan Step" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No target workflow"
  end

  # ── meta_create_sub_step ──

  test "meta_create_sub_step creates sub-step" do
    wf = create(:workflow, scope: @project)
    step = create(:step, workflow: wf)

    result = InternalTools::MetaCreateSubStep.new(
      params: { step_id: step.id, name: "Sub 1" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Sub 1", data["name"]
    assert_equal step.id, data["step_id"]
  end

  # ── meta_get_workflow ──

  test "meta_get_workflow returns full workflow structure" do
    wf = create(:workflow, scope: @project, name: "Full WF")
    step = create(:step, workflow: wf, name: "S1", position: 1, instructions: "Do it")
    create(:sub_step, step: step, name: "SS1", position: 1)
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaGetWorkflow.new(
      params: {},
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Full WF", data["name"]
    assert_equal 1, data["steps_count"]
    assert_equal "S1", data["steps"][0]["name"]
    assert_equal 1, data["steps"][0]["sub_steps"].size
  end

  # ── meta_list_workflows ──

  test "meta_list_workflows lists project and company workflows" do
    create(:workflow, scope: @project, name: "Project WF")
    create(:workflow, scope: @project, name: "Company WF")

    result = InternalTools::MetaListWorkflows.new(
      params: {},
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_operator data["workflows_count"], :>=, 2
    names = data["workflows"].map { |w| w["name"] }
    assert_includes names, "Project WF"
    assert_includes names, "Company WF"
  end

  # ── meta_finalize_workflow ──

  test "meta_finalize_workflow returns valid for complete workflow" do
    wf = create(:workflow, scope: @project)
    agent = Agent.create!(scope: @project, name: "test_agent", title: "Test", persona: "Test agent")
    step = create(:step, workflow: wf, name: "S1", position: 1, instructions: "Do it", agent: agent)
    create(:sub_step, step: step, name: "SS1", position: 1)
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaFinalizeWorkflow.new(
      params: {},
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert data["valid"]
    assert_includes data["summary"], "valid"
  end

  test "meta_finalize_workflow returns errors for incomplete workflow" do
    wf = create(:workflow, scope: @project)
    create(:step, workflow: wf, name: "No Instructions", position: 1, instructions: nil)
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaFinalizeWorkflow.new(
      params: {},
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    refute data["valid"]
    assert data["errors"].any? { |e| e.include?("no instructions") }
  end

  test "meta_finalize_workflow detects empty workflow" do
    wf = create(:workflow, scope: @project)
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaFinalizeWorkflow.new(
      params: {},
      session: @session
    ).execute

    data = JSON.parse(result[:stdout])
    refute data["valid"]
    assert data["errors"].any? { |e| e.include?("no steps") }
  end

  test "meta_finalize_workflow flags a non-existent linked asset_id" do
    wf = create(:workflow, scope: @project)
    agent = Agent.create!(scope: @project, name: "a1", title: "T", persona: "p")
    create(:step, workflow: wf, name: "S1", position: 1, instructions: "Do it", agent: agent,
                  asset_ids: [ 999_999 ])
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaFinalizeWorkflow.new(params: {}, session: @session).execute

    data = JSON.parse(result[:stdout])
    refute data["valid"]
    assert data["errors"].any? { |e| e.include?("non-existent asset_id 999999") }
  end

  # ── meta_link_resource_to_step ──

  test "meta_link_resource_to_step links an asset to a step" do
    wf = create(:workflow, scope: @project)
    step = create(:step, workflow: wf, name: "S1")
    asset = create(:asset, scope: @project, created_by: @user)

    result = InternalTools::MetaLinkResourceToStep.new(
      params: { step_id: step.id, resource_type: "asset", resource_id: asset.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_equal [ asset.id ], step.reload.asset_ids
  end

  # ── meta_update_step ──

  test "meta_update_step updates step fields" do
    wf = create(:workflow, scope: @project)
    step = create(:step, workflow: wf, name: "Old Name", instructions: "Old")

    result = InternalTools::MetaUpdateStep.new(
      params: { step_id: step.id, name: "New Name", instructions: "New instructions" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    step.reload
    assert_equal "New Name", step.name
    assert_equal "New instructions", step.instructions
  end

  # ── meta_delete_step ──

  test "meta_delete_step deletes step without dependents" do
    wf = create(:workflow, scope: @project)
    step = create(:step, workflow: wf, name: "Deletable", position: 1)

    result = InternalTools::MetaDeleteStep.new(
      params: { step_id: step.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_nil Step.find_by(id: step.id)
  end

  test "meta_delete_step fails if other steps depend on it" do
    wf = create(:workflow, scope: @project)
    step1 = create(:step, workflow: wf, name: "Parent", position: 1)
    create(:step, workflow: wf, name: "Child", position: 2, depends_on_step_ids: [ step1.id ])

    result = InternalTools::MetaDeleteStep.new(
      params: { step_id: step1.id },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "depend on it"
  end

  # ── meta_delete_workflow ──

  test "meta_delete_workflow soft-deletes a project workflow and returns deleted: true" do
    wf = create(:workflow, scope: @project, name: "Disposable WF")

    result = InternalTools::MetaDeleteWorkflow.new(
      params: { workflow_id: wf.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert data["deleted"]
    assert_equal "Disposable WF", data["workflow_name"]

    # Soft delete keeps the row but stamps deleted_at and drops it from the active scope
    wf.reload
    assert wf.deleted?
    assert_not_nil wf.deleted_at
    assert_not Workflow.active.exists?(wf.id)
    assert Workflow.exists?(wf.id)
  end

  test "meta_delete_workflow soft-deletes a company-scoped workflow" do
    wf = create(:workflow, scope: @project, name: "Company Disposable")

    result = InternalTools::MetaDeleteWorkflow.new(
      params: { workflow_id: wf.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert data["deleted"]
    assert_equal "Company Disposable", data["workflow_name"]
    assert wf.reload.deleted?
  end

  # ── context requirement ──

  test "meta tools raise error outside workflow context" do
    no_wf_session = Object.new
    no_wf_session.define_singleton_method(:step_run) { nil }
    no_wf_session.define_singleton_method(:project) { nil }

    assert_raises(InternalTools::WorkflowContextError) do
      InternalTools::MetaCreateWorkflow.new(
        params: { name: "Test" },
        session: no_wf_session
      ).execute
    end
  end

  # ── works with standalone session (no workflow context) ──

  test "meta tools work with standalone session (no step_run)" do
    standalone_session = Object.new
    standalone_session.define_singleton_method(:project) { @project }
    standalone_session.define_singleton_method(:step_run) { nil }
    standalone_session.define_singleton_method(:metadata) { {} }
    standalone_session.define_singleton_method(:update!) { |_| true }
    standalone_session.instance_variable_set(:@project, @project)

    result = InternalTools::MetaListWorkflows.new(
      params: {},
      session: standalone_session
    ).execute

    assert_equal 0, result[:exit_code]
  end
end
