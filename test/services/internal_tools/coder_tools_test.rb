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

    class << self
      attr_accessor :last_options
    end

    def initialize(integration:, terminal_session:)
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

  test "allocate: passes the caller's exclude list through to the allocator" do
    Coder::Allocator.stub(:new, ->(integration:, terminal_session:) {
      FakeAllocator.new(integration: integration, terminal_session: terminal_session)
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
    lock_service.acquire(workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @session.id)
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
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @session.id
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
      workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: @session.id
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

    def prepare(workspace_name:, repository:, path: nil)
      self.class.last_call = { workspace_name: workspace_name, repository: repository, path: path }
      { job_id: "j9", job_dir: "/var/lib/aixle-jobs", log_path: "/var/lib/aixle-jobs/j9.log",
        repository: repository.full_name, path: path || "/root/#{repository.repo_name}" }
    end
  end

  def hold_lock(workspace_name = "ws-1")
    Coder::LockService.new(@integration).acquire(
      workspace_name: workspace_name, workspace_id: "u1", terminal_session_id: @session.id
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
