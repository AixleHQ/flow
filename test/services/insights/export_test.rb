# frozen_string_literal: true

require "test_helper"

module Insights
  class ExportTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project, agent_type: "claude_code")
      @client = FakeInsightsClient.new
    end

    test "a session of an exported project is queued and sent right after commit" do
      @integration = connect_to_insights!(@project)
      create_list(:llm_call, 2, terminal_session: @session)

      assert_enqueued_with(job: ExportSessionJob) { Export.enqueue(@session) }

      export = InsightsSessionExport.find_by!(terminal_session: @session)
      assert_equal [ "pending", 2, @integration.id ], [ export.state, export.record_count, export.integration_id ]
    end

    test "nothing is queued for a project that is not exported, or for a session without records" do
      create(:llm_call, terminal_session: @session)
      Export.enqueue(@session)
      assert_not InsightsSessionExport.exists?

      connect_to_insights!(@project)
      Export.enqueue(create(:terminal_session, :running, user: @user, project: @project))
      assert_not InsightsSessionExport.exists?
    end

    test "a delivered session goes back to pending only when it gained rows" do
      connect_to_insights!(@project)
      create(:llm_call, terminal_session: @session)
      Export.enqueue(@session)
      export = InsightsSessionExport.last
      export.update!(state: "delivered")

      Export.enqueue(@session)
      assert_equal "delivered", export.reload.state

      create(:llm_call, terminal_session: @session)
      Export.enqueue(@session)
      assert_equal [ "pending", 2 ], [ export.reload.state, export.record_count ]
    end

    test "every chunk accepted delivers the session" do
      export = queued(3)

      assert_equal :delivered, deliver(export)

      assert_equal [ "delivered", 0 ], [ export.reload.state, export.rejected_count ]
      assert_equal 1, @client.exported.size
    end

    test "records refused in a partial success reject the session, and it is not retried" do
      export = queued(2)
      @client.export_results = [ Client::ExportResult.new(status: 200, rejected: 1, message: "record 1: bad id") ]

      assert_equal :rejected, deliver(export)

      export.reload
      assert_equal [ "rejected", 1 ], [ export.state, export.rejected_count ]
      assert_match "chunk 1/1: record 1: bad id", export.last_error
      assert_equal :not_due, deliver(export)
    end

    test "a refused connection stops its sends and leaves the session waiting for a new code" do
      export = queued(1)
      @client.export_results = [ Client::ExportResult.new(status: 401) ]

      assert_equal :connection_refused, deliver(export)

      assert_equal "pending", export.reload.state
      assert_equal "error", export.integration.reload.status
      assert_not InsightsSessionExport.due.exists?(export.id)
    end

    test "a chunk too large is split in half and re-sent" do
      export = queued(4)
      @client.export_results = [ Client::ExportResult.new(status: 413) ]

      assert_equal :delivered, Export.deliver(export.id, client: @client, chunk_size: 4)

      sizes = @client.exported.map { |p| p["resourceLogs"].first["scopeLogs"].first["logRecords"].size }
      assert_equal [ 4, 2, 2 ], sizes
    end

    test "a chunk that breaks the contract rejects its records" do
      export = queued(2)
      @client.export_results = [ Client::ExportResult.new(status: 422, message: "unknown agent type") ]

      assert_equal :rejected, deliver(export)
      assert_equal 2, export.reload.rejected_count
    end

    test "a rate limit waits for Retry-After" do
      export = queued(1)
      @client.export_results = [ Client::ExportResult.new(status: 429, retry_after: 30) ]

      freeze_time do
        assert_equal :retry, deliver(export)
        assert_equal 30.seconds.from_now, export.reload.next_attempt_at
      end
    end

    test "a server or network error backs off, and gives up after a week" do
      export = queued(1)
      @client.export_results = [ Client::ExportResult.new(status: 503) ]

      freeze_time do
        assert_equal :retry, deliver(export)
        assert_equal [ 1, 1.minute.from_now ], [ export.reload.attempts, export.next_attempt_at ]
      end

      export.update!(created_at: 8.days.ago, next_attempt_at: nil)
      @client.fail_next(:export_logs, Client::Error.new("Insights is unreachable: SocketError"))
      assert_equal :failed, deliver(export)
      assert_equal "failed", export.reload.state
    end

    test "a session claimed by one sender is not sent by another" do
      export = queued(1)
      export.update!(claimed_until: 5.minutes.from_now)

      assert_equal :not_due, deliver(export)
      assert_empty @client.exported
    end

    test "the cron sends what is due" do
      queued(1)

      assert_equal({ "delivered" => 1, "swept" => 1 }, ExportRelay.drain(client: @client))
    end

    private

    def queued(calls)
      connect_to_insights!(@project)
      create_list(:llm_call, calls, terminal_session: @session)
      Export.enqueue(@session)
      InsightsSessionExport.find_by!(terminal_session: @session)
    end

    def deliver(export) = Export.deliver(export.id, client: @client)
  end
end
