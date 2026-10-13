# frozen_string_literal: true

require "test_helper"
require "timeout"

class ProjectMemoryConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Settings.engram.stubs(:url).returns("http://engram:7437")
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company, memory_enabled: true)
    @session = create(:terminal_session, :running, project: @project, user: @user)
    @client = FakeEngramClient.new
  end

  teardown do
    MemoryRetrieval.where(project: @project).delete_all
    ProjectMemory.where(project: @project).delete_all
    @session&.delete
    @project&.repositories&.delete_all
    @project&.delete
    @user&.company_memberships&.delete_all
    UserIdentity.where(user: @user).delete_all
    UserSession.where(user: @user).delete_all
    @user&.delete
    CompanyAuthPolicy.where(company: @company).delete_all
    IdentityProvider.where(company: @company).delete_all
    @company&.delete
  end

  test "competing connections preserve the session retrieval quota" do
    outcomes = compete do |service|
      5.times.map { outcome { service.search(query: "finding") } }
    end.flatten

    assert_equal 5, outcomes.count(:ok)
    assert_equal 5, outcomes.count(:budget_exhausted)
    assert_equal 5, @session.reload.metadata.dig("project_memory", "retrieval_calls")
    assert_equal 5, @session.metadata.dig("project_memory", "retrieved_tokens")
  end

  test "competing connections cannot capture beyond the session quota" do
    outcomes = compete do |service|
      8.times.map do
        outcome { service.capture(title: "Finding", content: "Reviewed later", topic_key: "finding", sources: []) }
      end
    end.flatten

    assert_equal 10, outcomes.count(:ok)
    assert_equal 6, outcomes.count(:budget_exhausted)
    assert_equal 10, @session.reload.metadata.dig("project_memory", "captures")
    assert_equal 10, @project.project_memories.count
  end

  test "competing reviews accept only one proposal for the same base revision" do
    repository = create(:repository, :public_source, scope: @project)
    sources = [ { "repository_id" => repository.id, "path" => "README.md", "revision" => "a" * 40 } ]
    proposals = 2.times.map do
      @project.project_memories.create!(title: "Finding", content: "A reusable finding", topic_key: "finding")
    end
    work = Queue.new
    proposals.each { |proposal| work << proposal }
    outcomes = compete(review: true) do |service|
      proposal = work.pop
      outcome do
        service.validate!(memory: proposal, expected_revision: proposal.revision, evidence: "Reviewed",
                          sources: sources, reviewer: @user)
      end
    end

    assert_equal 1, outcomes.count(:ok)
    assert_equal 1, outcomes.count(:revision_conflict)
    assert_equal 1, @project.project_memories.where(state: "validated").count
    assert_equal 1, @project.project_memories.where(state: "pending").count
  end

  private

  def outcome
    yield
    :ok
  rescue ProjectMemoryService::Error => error
    error.code
  end

  def compete(review: false)
    ready = Queue.new
    gate = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          session = TerminalSession.find(@session.id) unless review
          service = ProjectMemoryService.new(session, project: Project.find(@project.id), client: @client,
                                              source_verifier: FakeMemorySourceVerifier.new)
          ready << connection.select_value("SELECT pg_backend_pid()").to_i
          gate.pop
          yield service
        end
      end
    end
    Timeout.timeout(15) do
      pids = 2.times.map { ready.pop }
      assert_equal 2, pids.uniq.size
      @project.with_lock do
        2.times { gate << true }
        connection = ActiveRecord::Base.lease_connection
        loop do
          connection.execute("SELECT pg_stat_clear_snapshot()")
          waiting = connection.select_value("SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{pids.join(',')}) AND wait_event_type = 'Lock'").to_i
          break if waiting == 2

          sleep 0.01
        end
      end
      threads.map(&:value)
    end
  ensure
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end
end
