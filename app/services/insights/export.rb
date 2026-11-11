# frozen_string_literal: true

module Insights
  # Delivers sessions to Aixle Insights at least once (docs/design/insights-usage-export.md
  # §6). A session is queued when its records are materialized and sent right after commit
  # by Insights::ExportSessionJob; Insights::ExportRelay, on a Temporal cron, sends whatever
  # is still due. A row is claimed with a lease rather than a lock, so no row lock is held
  # while Insights is being called, and a sender that dies is picked up when the lease ends.
  class Export
    LEASE = 10.minutes
    FIRST_RETRY = 1.minute
    LAST_RETRY = 6.hours
    GIVE_UP_AFTER = 7.days
    ERROR_LIMIT = 1_000

    # Raised for a chunk Insights refused, so the report names what went wrong.
    class Rejected < StandardError; end

    def self.enqueue(terminal_session)
      project = terminal_session.project
      return unless project&.exports_to_insights?

      total = record_count(terminal_session, project)
      return if total.zero?

      export = InsightsSessionExport.find_or_initialize_by(terminal_session: terminal_session)
      return if export.persisted? && export.record_count >= total && export.state != "pending"

      export.update!(integration: project.insights_connection, state: "pending", record_count: total,
                     attempts: 0, next_attempt_at: nil, last_error: nil)
      ActiveRecord.after_all_transactions_commit { ExportSessionJob.perform_later(export.id) }
    end

    def self.record_count(terminal_session, project)
      count = LlmCall.where(terminal_session_id: terminal_session.id).count
      return count unless project.shares_prompts_with_insights?

      count + AgentPrompt.where(terminal_session_id: terminal_session.id).count +
        AgentToolCall.where(terminal_session_id: terminal_session.id).count
    end

    def self.deliver(export_id, client: Client.build, now: Time.current, chunk_size: SessionPayload::CHUNK)
      claimed = InsightsSessionExport.due(now).where(id: export_id)
                                     .update_all(claimed_until: now + LEASE, updated_at: now)
      return :not_due if claimed.zero?

      new(InsightsSessionExport.find(export_id), client: client, now: now, chunk_size: chunk_size).deliver
    end

    def initialize(export, client:, now:, chunk_size:)
      @export = export
      @client = client
      @now = now
      @chunk_size = chunk_size
    end

    def deliver
      payload = SessionPayload.new(@export.terminal_session)
      slices = payload.records.each_slice(@chunk_size).to_a
      planned = slices.size
      rejected = 0
      messages = []
      index = 0

      until slices.empty?
        slice = slices.shift
        index += 1
        where = "chunk #{index}/#{planned}"
        result = @client.export_logs(secret, payload.request(slice))

        if result.accepted?
          next
        elsif result.partially_rejected?
          rejected += result.rejected
          messages << "#{where}: #{result.message}"
        elsif [ 401, 403 ].include?(result.status)
          return refused_connection("#{where}: Insights refused the connection (#{result.status})")
        elsif result.status == 413 && slice.size > 1
          slices.unshift(*slice.each_slice((slice.size / 2.0).ceil).to_a)
        elsif [ 413, 422 ].include?(result.status)
          rejected += slice.size
          messages << "#{where}: #{result.status} #{result.message}".strip
        elsif result.status == 429
          return retry_at(@now + (result.retry_after || FIRST_RETRY.to_i).seconds, "#{where}: rate limited")
        else
          return back_off("#{where}: Insights answered #{result.status}")
        end
      end

      finish(rejected, messages)
    rescue Client::Error => e
      back_off("chunk #{index}: #{e.message}")
    end

    private

    def secret
      @secret ||= @export.integration.credentials_data.fetch("secret")
    end

    def finish(rejected, messages)
      if rejected.zero?
        @export.update!(state: "delivered", delivered_at: @now, rejected_count: 0, last_error: nil, claimed_until: nil)
        return :delivered
      end

      message = messages.join("; ").truncate(ERROR_LIMIT)
      @export.update!(state: "rejected", rejected_count: rejected, last_error: message, claimed_until: nil)
      Rails.error.report(Rejected.new(message), handled: true, severity: :error, source: "insights.export",
                                                context: { insights_session_export_id: @export.id, rejected: rejected })
      :rejected
    end

    # The connection's secret no longer works: the integration asks for a new code, and the
    # row waits for it (due skips a connection that is not active).
    def refused_connection(message)
      @export.integration.update!(status: "error")
      @export.update!(last_error: message, claimed_until: nil)
      :connection_refused
    end

    def retry_at(time, message)
      @export.update!(next_attempt_at: time, last_error: message, claimed_until: nil)
      :retry
    end

    def back_off(message)
      attempts = @export.attempts + 1
      if @export.created_at < @now - GIVE_UP_AFTER
        @export.update!(state: "failed", attempts: attempts, last_error: message.truncate(ERROR_LIMIT), claimed_until: nil)
        return :failed
      end

      delay = [ FIRST_RETRY * (2**(attempts - 1)), LAST_RETRY ].min
      @export.update!(attempts: attempts, next_attempt_at: @now + delay, last_error: message.truncate(ERROR_LIMIT),
                      claimed_until: nil)
      :retry
    end
  end
end
