# frozen_string_literal: true

require "test_helper"

class InternalTools::CoderToolsTest < ActiveSupport::TestCase
  setup do
    @company     = create(:company)
    @user        = create(:user, :admin, company: @company)
    @project     = create(:project, company: @company, owner: @user)
    @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
    @other       = create(:integration, :coder, :active, company: @company, connected_by: @user)

    @mcp_a = create_managed_server(@integration)
    @mcp_b = create_managed_server(@other)

    project = @project
    integration_id = @integration.id
    @session = Object.new
    @session.define_singleton_method(:id) { 4242 }
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { OpenStruct.new(id: 1) }
    @session.define_singleton_method(:user) { nil }

    @no_workflow_session = Object.new
    @no_workflow_session.define_singleton_method(:id) { 4242 }
    @no_workflow_session.define_singleton_method(:project) { nil }
    @no_workflow_session.define_singleton_method(:step_run) { nil }
    @no_workflow_session.define_singleton_method(:user) { nil }
  end

  def create_managed_server(integration)
    MCPServer.create!(
      name:         "coder-#{integration.id}",
      display_name: "Coder #{integration.id}",
      kind:         :managed,
      transport:    :http,
      integration:  integration,
      scope:        @company,
      enabled:      true
    )
  end

  # ---------- coder_allocate_machine ----------

  test "allocate: errors without an MCP server context" do
    handler = InternalTools::CoderAllocateMachine.new(params: {}, session: @session)
    result = handler.execute

    assert_equal 1, result[:exit_code]
    assert_match(/managed Coder MCP server/, result[:stderr])
  end

  test "allocate: works without workflow context when MCP server is present" do
    Coder::Allocator.stub(:new, ->(integration:, terminal_session:) {
      FakeAllocator.new(integration: integration, terminal_session: terminal_session)
    }) do
      handler = InternalTools::CoderAllocateMachine.new(
        params: {}, session: @no_workflow_session, mcp_server: @mcp_a
      )
      result = handler.execute

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      assert_equal "ws-1", payload["workspace_name"]
    end
  end

  test "allocate: errors without workflow context only when MCP server is missing" do
    handler = InternalTools::CoderAllocateMachine.new(
      params: {}, session: @no_workflow_session
    )
    result = handler.execute

    assert_equal 1, result[:exit_code]
    assert_match(/managed Coder MCP server/, result[:stderr])
  end

  class FakeAllocator
    attr_reader :integration

    def initialize(integration:, terminal_session:)
      @integration = integration
    end

    def allocate(**_opts)
      { workspace_name: "ws-1", workspace_id: "u1", status: "running" }
    end
  end

  test "allocate: dispatches to the allocator with the resolved integration" do
    captured = nil
    Coder::Allocator.stub(:new, ->(integration:, terminal_session:) {
      captured = integration
      FakeAllocator.new(integration: integration, terminal_session: terminal_session)
    }) do
      result = InternalTools::CoderAllocateMachine.new(
        params: {}, session: @session, mcp_server: @mcp_a
      ).execute

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      assert_equal "ws-1", payload["workspace_name"]
    end

    assert_equal @integration.id, captured.id
  end

  test "allocate: routes to the *exact* integration tied to the MCP server" do
    received = []
    Coder::Allocator.stub(:new, ->(integration:, terminal_session:) {
      received << integration.id
      FakeAllocator.new(integration: integration, terminal_session: terminal_session)
    }) do
      InternalTools::CoderAllocateMachine.new(params: {}, session: @session, mcp_server: @mcp_a).execute
      InternalTools::CoderAllocateMachine.new(params: {}, session: @session, mcp_server: @mcp_b).execute
    end

    assert_equal [ @integration.id, @other.id ], received
  end

  test "allocate: errors when the MCP server is not managed" do
    custom_server = create(:mcp_server, kind: :custom, scope: @company)
    handler = InternalTools::CoderAllocateMachine.new(
      params: {}, session: @session, mcp_server: custom_server
    )
    result = handler.execute

    assert_equal 1, result[:exit_code]
    assert_match(/managed Coder MCP server/, result[:stderr])
  end

  test "allocate: errors when the integration is inactive" do
    @integration.update!(status: :error)
    handler = InternalTools::CoderAllocateMachine.new(
      params: {}, session: @session, mcp_server: @mcp_a
    )
    result = handler.execute

    assert_equal 1, result[:exit_code]
    assert_match(/managed Coder MCP server/, result[:stderr])
  end

  # ---------- coder_ssh_exec ----------

  test "ssh_exec: rejects when session does not hold the lock" do
    handler = InternalTools::CoderSshExec.new(
      params: { workspace_name: "ws-1", command: "ls" },
      session: @session,
      mcp_server: @mcp_a
    )
    result = handler.execute

    assert_equal 1, result[:exit_code]
    assert_match(/does not hold the lock/, result[:stderr])
  end

  test "ssh_exec: works without workflow context when the session holds the lock" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @no_workflow_session.id
    )

    Coder::SshRunner.any_instance.stubs(:exec).returns(
      exit_code: 0, stdout: "hello", stderr: "", truncated: false
    )

    result = InternalTools::CoderSshExec.new(
      params: { workspace_name: "ws-1", command: "echo hello" },
      session: @no_workflow_session, mcp_server: @mcp_a
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "hello", payload["stdout"]
  end

  test "ssh_exec: runs the command when the session holds the lock" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @session.id
    )

    Coder::SshRunner.any_instance.stubs(:exec).returns(
      exit_code: 0, stdout: "hello", stderr: "", truncated: false
    )

    result = InternalTools::CoderSshExec.new(
      params: { workspace_name: "ws-1", command: "echo hello" },
      session: @session, mcp_server: @mcp_a
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal 0, payload["exit_code"]
    assert_equal "hello", payload["stdout"]
  end

  test "ssh_exec: respects the per-integration lock scope" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @session.id
    )

    handler = InternalTools::CoderSshExec.new(
      params: { workspace_name: "ws-1", command: "echo hello" },
      session: @session, mcp_server: @mcp_b
    )
    result = handler.execute

    assert_equal 1, result[:exit_code]
    assert_match(/does not hold the lock/, result[:stderr])
  end

  # ---------- coder_release_machine ----------

  test "release: idempotently releases the workspace lock" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @session.id
    )

    result = InternalTools::CoderReleaseMachine.new(
      params: { workspace_name: "ws-1" },
      session: @session, mcp_server: @mcp_a
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "ws-1", payload["workspace_name"]
    assert payload["released"]
    assert_not Coder::LockService.new(@integration).held?(workspace_name: "ws-1")
  end

  test "release: returns released=false when nothing was held" do
    result = InternalTools::CoderReleaseMachine.new(
      params: { workspace_name: "ws-missing" },
      session: @session, mcp_server: @mcp_a
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_not payload["released"]
  end

  test "release: works without workflow context" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @no_workflow_session.id
    )

    result = InternalTools::CoderReleaseMachine.new(
      params: { workspace_name: "ws-1" },
      session: @no_workflow_session, mcp_server: @mcp_a
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "ws-1", payload["workspace_name"]
    assert payload["released"]
  end

  # DD-13 regression: a session that does NOT own the lock must not be able
  # to delete the owning session's row.
  test "release: does not delete a lock held by a different session" do
    owner_session_id = 9001
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: owner_session_id
    )

    # @session.id is 4242, so this call comes from a non-owning session.
    result = InternalTools::CoderReleaseMachine.new(
      params: { workspace_name: "ws-1" },
      session: @session, mcp_server: @mcp_a
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_not payload["released"], "non-owner must see released=false"
    assert Coder::LockService.new(@integration).held_by_session?(
      workspace_name: "ws-1", terminal_session_id: owner_session_id
    ), "owner's lock row must survive"
  end
end
