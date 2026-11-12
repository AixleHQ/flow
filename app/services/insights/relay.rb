# frozen_string_literal: true

module Insights
  # Forwards the agents' own OTLP to Aixle Insights (docs/design/insights-otlp-relay.md §5).
  #
  # .capture runs in the usage ingest, once a batch has proven its sessions: what belongs
  # to a session of an exported project is enriched, masked and written to the outbox.
  # .drain, on a Temporal cron, sends each connection's due rows — merged per signal up to
  # MAX_RECORDS — and deletes what Insights accepted. A row is claimed with a lease, so no
  # lock is held while Insights is called and a sender that dies is picked up later.
  class Relay
    LEASE = 10.minutes
    FIRST_RETRY = 1.minute
    LAST_RETRY = 6.hours
    GIVE_UP_AFTER = 7.days
    KEEP_FAILED = 7.days
    MAX_RECORDS = 1_000
    MAX_BYTES = 4.megabytes
    ROWS_PER_DRAIN = 500
    ERROR_LIMIT = 255

    # Raised for records Insights refused, so the report names what went wrong.
    class Rejected < StandardError; end

    # Never lets the relay fail the ingest: Flow's own usage is recorded either way.
    def self.capture(payload, sessions)
      exported = sessions.select { |session| session.project&.exports_to_insights? }
      return if exported.empty?

      OtlpEnvelope.parts(payload, exported.index_by(&:route_token)).each do |part|
        project = part.session.project
        InsightsOtlpBatch.create!(integration: project.insights_connection, project: project,
                                  terminal_session: part.session, signal: part.signal,
                                  payload: InsightsOtlpBatch.wrap(part.request), record_count: part.record_count)
      end
    rescue StandardError => e
      Rails.error.report(e, handled: true, severity: :error, source: "insights.relay")
    end

    def self.drain(now: Time.current, client: Client.build)
      InsightsOtlpBatch.where(state: "failed").where(updated_at: ...(now - KEEP_FAILED)).delete_all
      Integration.active.where(provider: "insights").find_each.to_h do |integration|
        [ integration.id, new(integration, client: client, now: now).drain ]
      end
    end

    def initialize(integration, client:, now:)
      @integration = integration
      @client = client
      @now = now
      @outcome = Hash.new(0)
    end

    def drain
      rows = claim
      InsightsOtlpBatch::SIGNALS.each do |signal|
        groups = group(rows.select { |row| row.signal == signal })
        deliver(signal, groups) until groups.empty? || @halted
        release(groups.flatten) if @halted
      end
      @outcome.merge("claimed" => rows.size)
    end

    private

    def claim
      ids = InsightsOtlpBatch.due(@now).where(integration: @integration).order(:id).limit(ROWS_PER_DRAIN).pluck(:id)
      lease = (@now + LEASE).floor(6)
      InsightsOtlpBatch.due(@now).where(id: ids).update_all(claimed_until: lease, updated_at: @now)
      InsightsOtlpBatch.where(id: ids, claimed_until: lease).order(:id).to_a
    end

    def group(rows)
      rows.slice_before(new_group_tracker).to_a
    end

    # Starts a new request when adding the row would pass either limit; a row over a limit
    # on its own is still sent alone, and Insights answers 413 if it is too big.
    def new_group_tracker
      records = 0
      bytes = 0
      lambda do |row|
        fresh = records.positive? && (records + row.record_count > MAX_RECORDS || bytes + row.payload.bytesize > MAX_BYTES)
        records = 0 if fresh
        bytes = 0 if fresh
        records += row.record_count
        bytes += row.payload.bytesize
        fresh
      end
    end

    def deliver(signal, groups)
      rows = groups.shift
      result = @client.export(secret, signal, merge(rows))

      if result.accepted?
        done(rows)
      elsif result.partially_rejected?
        failed(rows, "Insights refused #{result.rejected} of #{rows.sum(&:record_count)} #{signal} records: #{result.message}")
      elsif [ 401, 403 ].include?(result.status)
        refused_connection(rows)
      elsif result.status == 413 && rows.size > 1
        groups.unshift(*rows.each_slice((rows.size / 2.0).ceil).to_a)
      elsif [ 400, 413, 422 ].include?(result.status)
        failed(rows, "Insights refused the #{signal} batch: #{result.status} #{result.message}".strip)
      elsif result.status == 429
        wait(rows, @now + (result.retry_after || FIRST_RETRY.to_i).seconds, "rate limited")
      else
        back_off(rows, "Insights answered #{result.status}")
      end
    rescue Client::Error => e
      back_off(rows, e.message)
    end

    def merge(rows)
      key = OtlpEnvelope::KEYS.fetch(rows.first.signal)
      { key => rows.flat_map { |row| row.request.fetch(key, []) } }
    end

    def secret
      @secret ||= @integration.credentials_data.fetch("secret")
    end

    def done(rows)
      InsightsOtlpBatch.where(id: rows.map(&:id)).delete_all
      @outcome["delivered"] += rows.size
    end

    def failed(rows, message)
      InsightsOtlpBatch.where(id: rows.map(&:id))
                       .update_all(state: "failed", last_error: message.truncate(ERROR_LIMIT), claimed_until: nil, updated_at: @now)
      Rails.error.report(Rejected.new(message), handled: true, severity: :error, source: "insights.relay",
                                                context: { integration_id: @integration.id, rows: rows.size })
      @outcome["failed"] += rows.size
    end

    # The secret no longer works: the card asks for a new code, and the rows wait for it
    # (drain skips a connection that is not active).
    def refused_connection(rows)
      @integration.update!(status: "error")
      release(rows, "Insights refused the connection")
      @halted = true
    end

    def wait(rows, time, message)
      release(rows, message, next_attempt_at: time)
      @halted = true
    end

    def back_off(rows, message)
      expired, waiting = rows.partition { |row| row.created_at < @now - GIVE_UP_AFTER }
      failed(expired, "Gave up after #{GIVE_UP_AFTER.inspect}: #{message}") if expired.any?
      waiting.group_by(&:attempts).each do |attempts, same|
        delay = [ FIRST_RETRY * (2**attempts), LAST_RETRY ].min
        InsightsOtlpBatch.where(id: same.map(&:id))
                         .update_all(attempts: attempts + 1, next_attempt_at: @now + delay,
                                     last_error: message.truncate(ERROR_LIMIT), claimed_until: nil, updated_at: @now)
      end
      @halted = true
    end

    def release(rows, message = nil, next_attempt_at: nil)
      return if rows.empty?

      changes = { claimed_until: nil, updated_at: @now }
      changes[:last_error] = message.truncate(ERROR_LIMIT) if message
      changes[:next_attempt_at] = next_attempt_at if next_attempt_at
      InsightsOtlpBatch.where(id: rows.map(&:id)).update_all(changes)
    end
  end
end
