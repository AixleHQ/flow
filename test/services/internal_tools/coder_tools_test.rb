# frozen_string_literal: true

require "test_helper"

class InternalTools::CoderToolsTest < ActiveSupport::TestCase
  setup do
    @company     = create(:company)
    @user        = create(:user, :admin, company: @company)
    @project     = create(:project, company: @company, owner: @user)
    # Company-wide (project_id nil) active Coder integration — resolved directly
    # from the session's project by Concerns::CoderResolver.
    @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)

    project = @project
    @session = Object.new
    @session.define_singleton_method(:id) { 4242 }
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { OpenStruct.new(id: 1) }
    @session.define_singleton_method(:user) { nil }

    # Same project (so the integration still resolves) but no step_run — exercises
    # the tools running outside of a workflow context.
    @no_workflow_session = Object.new
    @no_workflow_session.define_singleton_method(:id) { 4242 }
    @no_workflow_session.define_singleton_method(:project) { project }
    @no_workflow_session.define_singleton_method(:step_run) { nil }
    @no_workflow_session.define_singleton_method(:user) { nil }
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

  # ---------- coder_allocate_machine ----------

  test "allocate: errors when there is no active Coder integration for the project" do
    @integration.update!(status: :error)

    result = InternalTools::CoderAllocateMachine.new(params: {}, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_match(/No active Coder integration for this project/, result[:stderr])
  end

  test "allocate: dispatches to the allocator with the integration resolved from the session project" do
    captured = nil
    Coder::Allocator.stub(:new, ->(integration:, terminal_session:) {
      captured = integration
      FakeAllocator.new(integration: integration, terminal_session: terminal_session)
    }) do
      result = InternalTools::CoderAllocateMachine.new(params: {}, session: @session).execute

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      assert_equal "ws-1", payload["workspace_name"]
    end

    assert_equal @integration.id, captured.id
  end

  test "allocate: works without workflow context when an active integration is present" do
    Coder::Allocator.stub(:new, ->(integration:, terminal_session:) {
      FakeAllocator.new(integration: integration, terminal_session: terminal_session)
    }) do
      result = InternalTools::CoderAllocateMachine.new(
        params: {}, session: @no_workflow_session
      ).execute

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      assert_equal "ws-1", payload["workspace_name"]
    end
  end

  # ---------- coder_ssh_exec ----------

  test "ssh_exec: rejects when session does not hold the lock" do
    handler = InternalTools::CoderSshExec.new(
      params: { workspace_name: "ws-1", command: "ls" },
      session: @session
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
      session: @no_workflow_session
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
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal 0, payload["exit_code"]
    assert_equal "hello", payload["stdout"]
  end

  # ---------- coder_release_machine ----------

  test "release: idempotently releases the workspace lock" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @session.id
    )

    result = InternalTools::CoderReleaseMachine.new(
      params: { workspace_name: "ws-1" },
      session: @session
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
      session: @session
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
      session: @no_workflow_session
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
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_not payload["released"], "non-owner must see released=false"
    assert Coder::LockService.new(@integration).held_by_session?(
      workspace_name: "ws-1", terminal_session_id: owner_session_id
    ), "owner's lock row must survive"
  end
end
