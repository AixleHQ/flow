# frozen_string_literal: true

module AixleInsights
  # Sends completed agent-session usage to each company's Aixle Insights org.
  #
  # Template: Billing::CapacityMeter — a scheduled sweep that reads candidates
  # and a ledger, pushes in the background, and recovers by replaying the ledger
  # on the next run rather than by retrying inline. The Temporal schedule (Task 7)
  # calls #call; this class owns the selection, batching, delivery and bookkeeping.
  #
  # Two levels of control (design §1):
  #   - Company: an active Insights connection (Integration.aixle_insights_for).
  #     A company with none is skipped entirely — nothing it ran is sent.
  #   - Project: the per-project opt-in (Project#insights_sharing_enabled?).
  #
  # Candidates are terminal (finished/failed/cancelled) agent sessions whose
  # project opted in, that have llm_calls to send, and have no ledger row yet.
  # They are GROUPED BY COMPANY so a company's token is resolved once and used
  # for all its sessions. A candidate whose work ended past the replay window is
  # recorded `skipped!` rather than sent — Insights would drop it anyway.
  #
  # Idempotence: a session gets at most one ledger row (unique index on
  # terminal_session_id). Delivery is per session — a failed send is recorded
  # `failed!` and replayed next run; past the window it is `skipped!`.
  class UsageExporter
    REPLAY_WINDOW = InsightsUsageExport::REPLAY_WINDOW

    def initialize(client: Client, now: Time.current)
      @client = client
      @now = now.utc
    end

    attr_reader :client, :now

    # Export fresh candidates and replay any unsent ledger rows. Returns a
    # summary: how many sessions were exported, failed and skipped.
    def call
      return disabled_summary unless Settings.aixle_insights.enabled

      # Rows left unsent by earlier runs, captured BEFORE this run writes any new
      # ones — so a session that fails here is replayed next run, not twice now.
      replay_ids = InsightsUsageExport.unsent.pluck(:id)

      fresh = export_fresh_candidates
      replayed = replay(replay_ids)

      {
        exported: fresh[:exported] + replayed[:exported],
        failed: fresh[:failed] + replayed[:failed],
        skipped: fresh[:skipped] + replayed[:skipped]
      }
    end

    private

    def export_fresh_candidates
      exported = 0
      failed = 0
      skipped = 0

      candidate_sessions_by_company.each do |company, sessions|
        connection = Integration.aixle_insights_for(company)
        # No connection ⇒ the whole company is skipped: nothing is sent and no
        # ledger row is written, so it becomes a candidate again once connected.
        next if connection.nil?

        token = connection.insights_ingest_token
        next if token.blank?

        sessions.each do |session|
          case export_session(session, company: company, token: token)
          when :exported then exported += 1
          when :failed then failed += 1
          when :skipped then skipped += 1
          end
        end
      end

      { exported: exported, failed: failed, skipped: skipped }
    end

    # Exports one session under its company's token, recording the outcome in
    # the ledger. The ledger row is claimed first (pending), so a crash mid-send
    # leaves a replayable row rather than silently dropping the session.
    def export_session(session, company:, token:)
      ledger = InsightsUsageExport.find_or_create_by!(terminal_session_id: session.id) do |row|
        row.company_id = company.id
        row.state = "pending"
      end
      return :noop if ledger.state == "exported"

      deliver(session, ledger: ledger, token: token)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    # Builds and sends one session's batch, settling the ledger row. A session
    # whose work ended past the replay window can never be attributed, so it is
    # abandoned (skipped) rather than sent to a collector that will drop it.
    def deliver(session, ledger:, token:)
      if finished_before_window?(session)
        ledger.skipped!
        return :skipped
      end

      payload = OtlpLogsBuilder.new(session).build
      # A terminal session with no llm_calls has nothing to attribute. Mark it
      # exported with zero records so it is not reconsidered every run.
      if payload.nil?
        ledger.exported!(0)
        return :exported
      end

      client.post_logs(payload: payload, token: token)
      ledger.exported!(record_count(payload))
      :exported
    rescue StandardError => e
      ledger.failed!(e.message)
      :failed
    end

    # Terminal agent sessions whose project opted in, that have usage to send,
    # with NO ledger row yet — grouped by company. No window filter here: a
    # session that ended past the window still gets a ledger row (skipped), so it
    # is recorded once and not reconsidered every run. A session that already has
    # a row is left to the replay pass, so it is never processed by both.
    def candidate_sessions_by_company
      scope = TerminalSession
              .agent_sessions
              .where(state: TerminalSession::TERMINAL_STATES)
              .where(project_id: opted_in_project_ids)
              .where(id: LlmCall.select(:terminal_session_id).distinct)
              .where.not(id: ledgered_session_ids)
              .includes(:user, :project, :company)

      scope.group_by { |session| session.company || session.project&.company }
           .reject { |company, _| company.nil? }
    end

    def opted_in_project_ids
      Project.where("projects.settings->>'insights_sharing_enabled' = 'true'").select(:id)
    end

    def ledgered_session_ids
      InsightsUsageExport.select(:terminal_session_id)
    end

    # Replays the ledger rows captured as unsent at the start of the run. Each is
    # rebuilt from its session and resent under the company's current token.
    def replay(ledger_ids)
      exported = 0
      failed = 0
      skipped = 0

      InsightsUsageExport.where(id: ledger_ids)
                         .includes(terminal_session: [ :user, :project, :company ]).find_each do |ledger|
        session = ledger.terminal_session
        company = session&.company || session&.project&.company
        connection = company && Integration.aixle_insights_for(company)
        token = connection&.insights_ingest_token

        # Can't resolve a connection/token now (e.g. the company disconnected):
        # leave the row unsent for a later run, unless it has aged out.
        if token.blank?
          if finished_before_window?(session)
            ledger.skipped!
            skipped += 1
          end
          next
        end

        case deliver(session, ledger: ledger, token: token)
        when :exported then exported += 1
        when :failed then failed += 1
        when :skipped then skipped += 1
        end
      end

      { exported: exported, failed: failed, skipped: skipped }
    end

    def record_count(payload)
      payload[:resourceLogs].sum { |rl| rl[:scopeLogs].sum { |sl| sl[:logRecords].size } }
    end

    def window_start
      now - REPLAY_WINDOW
    end

    def finished_before_window?(session)
      finished_at = session&.finished_at
      finished_at.nil? || finished_at < window_start
    end

    def disabled_summary
      { exported: 0, failed: 0, skipped: 0, disabled: true }
    end
  end
end
