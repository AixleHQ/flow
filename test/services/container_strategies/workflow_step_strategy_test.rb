# frozen_string_literal: true

require "test_helper"

module ContainerStrategies
  class WorkflowStepStrategyTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
    end

    teardown do
      cleanup_runtime_overrides
    end

    # == Inheritance / static config ==

    test "inherits from AgentSessionStrategy" do
      assert_operator WorkflowStepStrategy, :<, AgentSessionStrategy
    end

    test "session_type is workflow_step" do
      assert_equal "workflow_step", minimal_strategy.send(:session_type)
    end

    test "services_ports exposes only the ttyd port" do
      assert_equal [ 7681 ], minimal_strategy.send(:services_ports)
    end

    test "build_labels marks the session as workflow_step" do
      labels = minimal_strategy.build_labels

      assert_equal "workflow_step", labels["aixle.session_type"]
      assert_equal "claude_code", labels["aixle.agent_type"]
    end

    test "phase_config returns workflow-step timeouts per phase" do
      strategy = minimal_strategy

      assert_equal({ timeout: 600 }, strategy.phase_config(:pull_image))
      assert_equal(
        { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 },
        strategy.phase_config(:exec)
      )
      assert_equal(
        { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } },
        strategy.phase_config(:cleanup)
      )
      assert_equal({ timeout: 300 }, strategy.phase_config(:something_else))
    end

    # == build_env_vars ==

    test "build_env_vars sets AGENT_PROMPT from step instructions and agent persona/principles" do
      agent = create(:agent, :with_project_scope, persona: "You are a QA reviewer.", principles: "Verify everything.")
      session, = create_workflow_step_session(instructions: "Review the pull request", agent: agent)
      strategy = build_strategy(session: session)

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "AGENT_PROMPT=Review the pull request"
      assert_includes env_vars, "CONFIGURED_AGENT_PERSONA=You are a QA reviewer."
      assert_includes env_vars, "CONFIGURED_AGENT_PRINCIPLES=Verify everything."
      assert_includes env_vars, "SESSION_TYPE=workflow_step"
    end

    test "build_env_vars omits agent persona vars when the step has no agent" do
      session, = create_workflow_step_session(instructions: "Just run it", agent: nil)
      strategy = build_strategy(session: session)

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "AGENT_PROMPT=Just run it"
      assert_not env_vars.any? { |v| v.start_with?("CONFIGURED_AGENT_PERSONA=") }
      assert_not env_vars.any? { |v| v.start_with?("CONFIGURED_AGENT_PRINCIPLES=") }
    end

    # == before_cleanup ==

    test "before_cleanup collects container outputs into WorkflowRunAssets and returns counts" do
      stub_container_runtime(agent_type: "claude_code")
      create(:agent_credential, user: @user, agent_type: "claude_code")
      session, step_run, _step, workflow_run = create_workflow_step_session
      strategy = build_strategy(session: session)

      result = nil
      assert_difference "WorkflowRunAsset.count", 1 do
        assert_no_difference "Asset.count" do # workflow outputs are WorkflowRunAssets, not Assets
          result = strategy.before_cleanup(container_id: "abc123")
        end
      end

      assert_equal 1, result[:outputs_count]
      assert_operator result[:logs_count], :>=, 1

      asset = workflow_run.workflow_run_assets.reload.last
      assert_equal "result.md", asset.name
      assert_equal step_run, asset.produced_by_step_run
      assert_equal "# Result\n\nGenerated output.\n".bytesize, asset.file_size
      assert asset.file.present?, "expected the collected output to have an attached file"

      assert_operator session.session_logs.reload.count, :>=, 1
    end

    test "before_cleanup returns empty hash when no container_id is given" do
      session, = create_workflow_step_session
      strategy = build_strategy(session: session)

      assert_equal({}, strategy.before_cleanup(container_id: nil))
    end

    # == inject_prior_step_outputs ==

    test "inject_prior_step_outputs downloads dependency outputs and run input assets into the container" do
      fake = stub_container_runtime(agent_type: "claude_code")
      Settings.stubs(:container_asset_host).returns(nil)

      workflow = create(:workflow, scope: @project)
      dep_step = create(:step, workflow: workflow, position: 1)
      current_step = create(:step, workflow: workflow, position: 2, depends_on_step_ids: [ dep_step.id ])
      workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
      dep_step_run = create(:step_run, workflow_run: workflow_run, step: dep_step)
      session = create(:terminal_session, :agent_session, user: @user, project: @project, agent_type: "claude_code")
      create(:step_run, workflow_run: workflow_run, step: current_step, terminal_session: session)

      # Output produced by the dependency step (wired to the current step via depends_on_step_ids).
      workflow_run.workflow_run_assets.create!(
        name: "prior.md", produced_by_step_run: dep_step_run,
        content_type: "text/markdown", file_size: 5,
        file: WorkflowRunAssetUploader.upload(StringIO.new("prior"), :store)
      )

      # Run-level input asset.
      input_asset = create(:asset, :with_company_scope, name: "brief.md", created_by: @user)
      create(:asset_version, :with_file, asset: input_asset, version: 1, uploaded_by: @user)
      workflow_run.update!(input_asset_ids: [ input_asset.id ])

      strategy = build_strategy(session: session)
      strategy.send(:inject_prior_step_outputs, "abc123")

      commands = fake.execs.map { |c| Array(c).join(" ") }
      assert commands.any? { |c| c.include?("mkdir") && c.include?("/workspace/assets") },
        "expected the assets dir to be created"
      assert commands.any? { |c| c.include?("curl") && c.include?("/workspace/assets/prior.md") },
        "expected the dependency output to be downloaded"
      assert commands.any? { |c| c.include?("curl") && c.include?("/workspace/assets/brief.md") },
        "expected the run input asset to be downloaded"
    end

    # == rewrite_url_for_container ==

    test "rewrite_url_for_container swaps host/scheme/port when a container asset host is configured" do
      Settings.stubs(:container_asset_host).returns("web:4000")

      rewritten = minimal_strategy.send(:rewrite_url_for_container, "https://minio.local:9000/bucket/out.md")

      uri = URI.parse(rewritten)
      assert_equal "http", uri.scheme
      assert_equal "web", uri.host
      assert_equal 4000, uri.port
      assert_equal "/bucket/out.md", uri.path
    end

    test "rewrite_url_for_container returns the url unchanged when no host is configured" do
      Settings.stubs(:container_asset_host).returns(nil)

      url = "https://minio.local:9000/bucket/out.md"
      assert_equal url, minimal_strategy.send(:rewrite_url_for_container, url)
    end

    private

    def minimal_strategy(agent_type: "claude_code")
      WorkflowStepStrategy.new(
        user_id: @user.id,
        agent_type: agent_type,
        session_id: 0,
        route_token: "tok-#{SecureRandom.hex(4)}",
        credential: nil
      )
    end

    def build_strategy(session:, agent_type: "claude_code", credential: nil)
      WorkflowStepStrategy.new(
        user_id: @user.id,
        agent_type: agent_type,
        session_id: session.id,
        route_token: session.route_token,
        credential: credential
      )
    end

    # Builds the workflow → step → run → step_run → session chain the strategy reads.
    # Returns [session, step_run, step, workflow_run].
    def create_workflow_step_session(instructions: "Do the thing", agent: nil)
      workflow = create(:workflow, scope: @project)
      step = create(:step, workflow: workflow, instructions: instructions, agent: agent)
      workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
      session = create(:terminal_session, :agent_session, user: @user, project: @project, agent_type: "claude_code")
      step_run = create(:step_run, workflow_run: workflow_run, step: step, terminal_session: session)
      [ session, step_run, step, workflow_run ]
    end
  end
end
