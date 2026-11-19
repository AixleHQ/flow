# frozen_string_literal: true

module Insights
  # Forwards the agents' own OTLP to Aixle Insights (docs/design/insights-otlp-relay.md §5).
  #
  # .capture runs in the usage ingest, once a batch has proven its sessions: what belongs
  # to a session of an exported project is enriched, masked and written to the outbox.
  # .drain, on a Temporal cron, sends each connection's due rows — rows of one resource
  # merged into one request, up to MAX_RECORDS — and deletes what Insights accepted. Unless
  # INSIGHTS_RESEND is on, it deletes what Insights refused too. A row is claimed with a
  # lease, so no lock is held while Insights is called and a sender that dies is picked up
  # later.
  class Relay
    LEASE = 10.minutes
    FIRST_RETRY = 1.minute
    LAST_RETRY = 6.hours
    GIVE_UP_AFTER = 7.days
    KEEP_FAILED = 7.days
    MAX_RECORDS = 1_000
    # Insights takes at most 5 MB gzipped and 50 MB inflated per request. Claude Code's raw
    # API bodies repeat the conversation and compress far better than 10:1.
    MAX_BYTES = 4.megabytes
    MAX_JSON_BYTES = 40.megabytes
    ROWS_PER_DRAIN = 500
    # Insights takes 60 requests a minute per connection, and a drain starts every minute.
    MAX_REQUESTS = 50
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
      queues = InsightsOtlpBatch::SIGNALS.map { |signal| [ signal, group(rows.select { |row| row.signal == signal }) ] }
      MAX_REQUESTS.times do
        break if @halted

        index = queues.index { |_signal, groups| groups.any? }
        break unless index

        signal, groups = queues.delete_at(index)
        deliver(signal, groups)
        queues << [ signal, groups ]
      end
      queues.each { |_signal, groups| release(groups.flatten) }
      @outcome.merge("claimed" => rows.size)
    end

    private

    def claim
      ids = InsightsOtlpBatch.due(@now).where(integration: @integration).order(:id).limit(ROWS_PER_DRAIN).pluck(:id)
      lease = (@now + LEASE).floor(6)
      InsightsOtlpBatch.due(@now).where(id: ids).update_all(claimed_until: lease, updated_at: @now)
      InsightsOtlpBatch.where(id: ids, claimed_until: lease).order(:id).to_a
    end

    # Insights takes one resource per request, so rows are grouped by theirs. Only the
    # resource and the size are kept: a drain's rows inflated at once could be gigabytes.
    def group(rows)
      shapes = rows.to_h { |row| [ row.id, shape_of(row) ] }
      rows.group_by { |row| shapes[row.id][:resource] }.values
          .flat_map { |same| same.slice_before(new_group_tracker(shapes)).to_a }
    end

    def shape_of(row)
      json = Zlib.gunzip(row.payload)
      { resource: JSON.parse(json).fetch(OtlpEnvelope::KEYS.fetch(row.signal)).first["resource"], json_bytes: json.bytesize }
    end

    # Starts a new request when adding the row would pass any limit; a row over a limit
    # on its own is still sent alone, and Insights answers 413 if it is too big.
    def new_group_tracker(shapes)
      records = bytes = json_bytes = 0
      lambda do |row|
        inflated = shapes[row.id][:json_bytes]
        fresh = records.positive? && (records + row.record_count > MAX_RECORDS || bytes + row.payload.bytesize > MAX_BYTES ||
                                      json_bytes + inflated > MAX_JSON_BYTES)
        records = bytes = json_bytes = 0 if fresh
        records += row.record_count
        bytes += row.payload.bytesize
        json_bytes += inflated
        fresh
      end
    end

    def deliver(signal, groups)
      rows = groups.shift
      result = @client.export(secret, signal, merge(rows))

      if result.accepted?
        done(rows)
      elsif [ 401, 403 ].include?(result.status)
        refused_connection(rows)
      elsif !Config.resend?
        let_go(signal, rows, result)
      elsif result.partially_rejected?
        failed(rows, "Insights refused #{result.rejected} of #{rows.sum(&:record_count)} #{signal} records: #{result.message}")
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
      scopes = OtlpEnvelope::SIGNALS.fetch(key)[:scopes]
      resources = rows.flat_map { |row| row.request.fetch(key, []) }
      { key => [ resources.first.merge(scopes => resources.flat_map { |resource| Array(resource[scopes]) }) ] }
    end

    def secret
      @secret ||= @integration.credentials_data.fetch("secret")
    end

    def done(rows)
      InsightsOtlpBatch.where(id: rows.map(&:id)).delete_all
      @outcome["delivered"] += rows.size
    end

    # Without INSIGHTS_RESEND, Insights' answer is final: the rows go, and the answer is logged.
    def let_go(signal, rows, result)
      InsightsOtlpBatch.where(id: rows.map(&:id)).delete_all
      records = rows.sum(&:record_count)
      if result.partially_rejected?
        @outcome["delivered"] += rows.size
        @outcome["records_refused"] += result.rejected
        lost = "#{result.rejected} of #{records}"
      else
        @outcome["let_go"] += rows.size
        lost = records.to_s
      end
      Rails.logger.info("[InsightsRelay] integration ##{@integration.id}: Insights answered #{result.status}, " \
                        "#{lost} #{signal} records not taken #{result.message.to_s.truncate(ERROR_LIMIT)}".strip)
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
