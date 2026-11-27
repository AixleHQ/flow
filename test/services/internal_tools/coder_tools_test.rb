# frozen_string_literal: true

require "test_helper"

class InternalTools::CoderToolsTest < ActiveSupport::TestCase
  setup do
    @company     = create(:company)
    @user        = create(:user, :admin, company: @company)
    @project     = create(:project, company: @company, owner: @user)
    # The integration is in the session's set: Concerns::CoderResolver reads the set,
    # not the project's integrations.
    @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)

    project = @project
    integration_ids = -> { [ @integration.id ] }
    @session = Object.new
    @session.define_singleton_method(:id) { 4242 }
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { OpenStruct.new(id: 1) }
    @session.define_singleton_method(:user) { nil }
    @session.define_singleton_method(:integrations) { Integration.where(id: integration_ids.call) }

    # Same project (so the integration still resolves) but no step_run — exercises
    # the tools running outside of a workflow context.
    @no_workflow_session = Object.new
    @no_workflow_session.define_singleton_method(:id) { 4242 }
    @no_workflow_session.define_singleton_method(:project) { project }
    @no_workflow_session.define_singleton_method(:step_run) { nil }
    @no_workflow_session.define_singleton_method(:user) { nil }
    @no_workflow_session.define_singleton_method(:integrations) { Integration.where(id: integration_ids.call) }
  end

  class FakeAllocator
    attr_reader :integration

    class << self
      attr_accessor :last_options
    end

    def initialize(integration:, holder:)
      @integration = integration
    end

    def allocate(**opts)
      self.class.last_options = opts
      { workspace_name: "ws-1", workspace_id: "u1", status: "running" }
    end
  end

  # Stands in for the app-owned Coder::SshRunner adapter through the
  # `SshRunner.new` seam.
  class FakeSshRunner
    attr_reader :detached, :status_calls

    def initialize(exec: nil, detached: nil, status: nil)
      @exec         = exec || { exit_code: 0, stdout: "ok", stderr: "", truncated: false }
      @detached     = detached || { job_id: "j1", job_dir: "/var/lib/aixle-jobs", log_path: "/var/lib/aixle-jobs/j1.log", detached: true }
      @status       = status || { job_id: "j1", state: "running", exit_code: nil, tail: "compiling\n" }
      @status_calls = []
    end

    def exec(**) = @exec
    def exec_detached(**) = @detached

    def job_status(**kwargs)
      @status_calls << kwargs
      @status
    end
  end

  # ---------- coder_allocate_machine ----------

  test "allocate: errors when the session's Coder integration is not active" do
    @integration.update!(status: :error)

    result = InternalTools::CoderAllocateMachine.new(params: {}, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_match(/is error, not active/, result[:stderr])
  end

  test "allocate: errors when no Coder integration is attached to the session" do
    @session.define_singleton_method(:integrations) { Integration.none }

    result = InternalTools::CoderAllocateMachine.new(params: {}, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_match(/No Coder integration is attached to this session/, result[:stderr])
  end

  test "allocate: with several attached integrations, leaving integration_id out lists them" do
    second = create(:integration, :coder, :active, company: @company, connected_by: @user, name: "Coder (second)")
    integration = @integration
    @session.define_singleton_method(:integrations) { Integration.where(id: [ integration.id, second.id ]) }

    result = InternalTools::CoderAllocateMachine.new(params: {}, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_match(/several Coder integrations: pass `integration_id`/, result[:stderr])
    assert_includes result[:stderr], "#{second.id} (Coder (second)"
  end

  test "allocate: integration_id picks one of several attached integrations" do
    second = create(:integration, :coder, :active, company: @company, connected_by: @user)
    integration = @integration
    @session.define_singleton_method(:integrations) { Integration.where(id: [ integration.id, second.id ]) }
    captured = nil

    Coder::Allocator.stub(:new, ->(integration:, terminal_session:) { captured = integration; FakeAllocator.new(integration: integration, terminal_session: terminal_session) }) do
      result = InternalTools::CoderAllocateMachine.new(params: { integration_id: second.id }, session: @session).execute
      assert_equal 0, result[:exit_code], result[:stderr]
    end

    assert_equal second.id, captured.id
  end

  test "allocate: an integration_id outside the session's set is refused, whatever the project has" do
    outside = create(:integration, :coder, :active, company: @company, connected_by: @user)

    result = InternalTools::CoderAllocateMachine.new(params: { integration_id: outside.id }, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_match(/Coder integration #{outside.id} is not attached to this session/, result[:stderr])
  end

  test "allocate: an integration_id that is not a number is refused" do
    result = InternalTools::CoderAllocateMachine.new(params: { integration_id: "abc" }, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_match(/integration_id must be an integer/, result[:stderr])
  end

  test "every Coder tool advertises an optional integration_id" do
    [ InternalTools::CoderAllocateMachine, InternalTools::CoderSshExec, InternalTools::CoderPrepareRepo,
      InternalTools::CoderJobStatus, InternalTools::CoderReleaseMachine ].each do |tool|
      schema = tool.tool_definition.input_schema
      assert schema.dig(:properties, :integration_id) || schema.dig("properties", "integration_id"), tool.name
      assert_not Array(schema[:required] || schema["required"]).include?("integration_id"), tool.name
    end
  end

  test "allocate: dispatches to the allocator with the integration resolved from the session project" do
    captured = nil
    Coder::Allocator.stub(:new, ->(integration:, holder:) {
      captured = integration
      FakeAllocator.new(integration: integration, holder: holder)
    }) do
      result = InternalTools::CoderAllocateMachine.new(params: {}, session: @session).execute

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      assert_equal "ws-1", payload["workspace_name"]
    end

    assert_equal @integration.id, captured.id
  end

  test "allocate: works without workflow context when an active integration is present" do
    Coder::Allocator.stub(:new, ->(integration:, holder:) {
      FakeAllocator.new(integration: integration, holder: holder)
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
      workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(@no_workflow_session.id)
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
      workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(@session.id)
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

  test "allocate: passes the caller's exclude list through to the allocator" do
    Coder::Allocator.stub(:new, ->(integration:, holder:) {
      FakeAllocator.new(integration: integration, holder: holder)
    }) do
      InternalTools::CoderAllocateMachine.new(
        params: { exclude: [ "ws-dead" ] }, session: @session
      ).execute
    end

    assert_equal [ "ws-dead" ], FakeAllocator.last_options[:exclude]
  end

  # The lock TTL has to measure silence rather than time since allocation, so
  # every use of the workspace renews it.
  test "ssh_exec: renews the lock it just used" do
    lock_service = Coder::LockService.new(@integration)
    lock_service.acquire(workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(@session.id))
    original = @integration.integration_data.find_by(key: "coder:workspace_lock:ws-1").expires_at

    travel 5.minutes do
      Coder::SshRunner.stub(:new, ->(_integration) { FakeSshRunner.new }) do
        InternalTools::CoderSshExec.new(
          params: { workspace_name: "ws-1", command: "true" }, session: @session
        ).execute
      end
    end

    assert_operator @integration.integration_data.find_by(key: "coder:workspace_lock:ws-1").expires_at,
                    :>, original
  end

  test "ssh_exec: detach returns a job id and points the caller at coder_job_status" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(@session.id)
    )

    result = Coder::SshRunner.stub(:new, ->(_integration) { FakeSshRunner.new }) do
      InternalTools::CoderSshExec.new(
        params: { workspace_name: "ws-1", command: "make check_all", detach: true },
        session: @session
      ).execute
    end

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "j1", payload["job_id"]
    assert_equal "/var/lib/aixle-jobs/j1.log", payload["log_path"]
    assert_match(/coder_job_status/, payload["next_step"])
  end

  # ---------- coder_job_status ----------

  test "job_status: returns the state and log tail of a detached job" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(@session.id)
    )
    runner = FakeSshRunner.new

    result = Coder::SshRunner.stub(:new, ->(_integration) { runner }) do
      InternalTools::CoderJobStatus.new(
        params: { workspace_name: "ws-1", job_id: "j1", tail_lines: 10 }, session: @session
      ).execute
    end

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "running", payload["state"]
    assert_equal "compiling\n", payload["tail"]
    assert_equal 10, runner.status_calls.first[:tail_lines]
  end

  test "job_status: rejects a session that does not hold the workspace lock" do
    result = InternalTools::CoderJobStatus.new(
      params: { workspace_name: "ws-1", job_id: "j1" }, session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/does not hold the lock/, result[:stderr])
  end

  # ---------- coder_prepare_repo ----------

  class FakeRepoBootstrap
    class << self
      attr_accessor :last_call
    end

    def initialize(_integration) = nil

    def prepare(workspace_name:, repository:, session:, path: nil, ref: nil)
      self.class.last_call = { workspace_name: workspace_name, repository: repository, session: session,
                               path: path, ref: ref }
      handle = { job_id: "j9", job_dir: "/var/lib/aixle-jobs", log_path: "/var/lib/aixle-jobs/j9.log",
                 repository: repository.full_name, path: path || "/root/#{repository.repo_name}" }
      ref ? handle.merge(ref: ref) : handle
    end
  end

  def hold_lock(workspace_name = "ws-1")
    Coder::LockService.new(@integration).acquire(
      workspace_name: workspace_name, workspace_id: "u1", holder: Coder::LockService::Holder.session(@session.id)
    )
  end

  test "prepare_repo: starts the bootstrap for the session's only repository" do
    github = create(:integration, :github, :active, company: @company, connected_by: @user)
    repo   = create(:repository, full_name: "acme/app", integration: github, scope: @project)
    @session.define_singleton_method(:repositories) { Repository.where(id: repo.id) }
    hold_lock

    result = Coder::RepoBootstrap.stub(:new, ->(integration) { FakeRepoBootstrap.new(integration) }) do
      InternalTools::CoderPrepareRepo.new(
        params: { workspace_name: "ws-1", path: "/root/app" }, session: @session
      ).execute
    end

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "j9", payload["job_id"]
    assert_equal "/root/app", payload["path"]
    assert_match(/coder_job_status/, payload["next_step"])
    assert_equal "acme/app", FakeRepoBootstrap.last_call[:repository].full_name
    assert_same @session, FakeRepoBootstrap.last_call[:session]
    assert_nil FakeRepoBootstrap.last_call[:ref]
    assert_not payload.key?("ref")
  end

  test "prepare_repo: forwards the requested ref and says where the resolved sha lands" do
    github = create(:integration, :github, :active, company: @company, connected_by: @user)
    repo   = create(:repository, full_name: "acme/app", integration: github, scope: @project)
    @session.define_singleton_method(:repositories) { Repository.where(id: repo.id) }
    hold_lock

    result = Coder::RepoBootstrap.stub(:new, ->(integration) { FakeRepoBootstrap.new(integration) }) do
      InternalTools::CoderPrepareRepo.new(
        params: { workspace_name: "ws-1", ref: "feature/login" }, session: @session
      ).execute
    end

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "feature/login", payload["ref"]
    assert_equal "feature/login", FakeRepoBootstrap.last_call[:ref]
    assert_match(/head_sha/, payload["next_step"])
    assert_match(/exit_code #{Coder::RepoBootstrap::REF_NOT_FOUND_EXIT_CODE}/, payload["next_step"])
  end

  test "prepare_repo: refuses an unsafe ref before it reaches the workspace" do
    github = create(:integration, :github, :active, company: @company, connected_by: @user)
    repo   = create(:repository, full_name: "acme/app", integration: github, scope: @project)
    @session.define_singleton_method(:repositories) { Repository.where(id: repo.id) }
    hold_lock

    result = InternalTools::CoderPrepareRepo.new(
      params: { workspace_name: "ws-1", ref: "main; rm -rf /" }, session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/is not a valid branch, tag or commit name/, result[:stderr])
  end

  test "prepare_repo: advertises ref as an optional parameter" do
    schema = InternalTools::CoderPrepareRepo.tool_definition.input_schema

    assert_equal %w[workspace_name], schema["required"]
    assert_not_nil schema.dig("properties", "ref")
  end

  test "prepare_repo: asks which repository when the session has several" do
    github = create(:integration, :github, :active, company: @company, connected_by: @user)
    one    = create(:repository, full_name: "acme/one", integration: github, scope: @project)
    two    = create(:repository, full_name: "acme/two", integration: github, scope: @project)
    @session.define_singleton_method(:repositories) { Repository.where(id: [ one.id, two.id ]) }
    hold_lock

    result = InternalTools::CoderPrepareRepo.new(
      params: { workspace_name: "ws-1" }, session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/pass `repository` to pick one/, result[:stderr])
    assert_match(/acme\/one/, result[:stderr])
  end

  test "prepare_repo: rejects a session that does not hold the workspace lock" do
    result = InternalTools::CoderPrepareRepo.new(
      params: { workspace_name: "ws-1" }, session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/does not hold the lock/, result[:stderr])
  end

  # ---------- coder_release_machine ----------

  test "release: idempotently releases the workspace lock" do
    Coder::LockService.new(@integration).acquire(
      workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(@session.id)
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
      workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(@no_workflow_session.id)
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
      workspace_name: "ws-1", workspace_id: "u1", holder: Coder::LockService::Holder.session(owner_session_id)
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
      workspace_name: "ws-1", holder: Coder::LockService::Holder.session(owner_session_id)
    ), "owner's lock row must survive"
  end
end
