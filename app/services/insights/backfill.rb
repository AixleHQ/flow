# frozen_string_literal: true

module Insights
  # A project switched on for Insights also sends its recent past
  # (docs/design/insights-usage-export.md §10, phase 5): its sessions that ended in the
  # last WINDOW are materialized and queued. They are left to the export's cron rather than
  # sent at once, so a busy project's history drains at the sweep's pace.
  class Backfill
    WINDOW = 30.days

    def self.call(project, now: Time.current)
      sessions = TerminalSession.where(project_id: project.id, state: TerminalSession::TERMINAL_STATES)
                                .where(finished_at: (now - WINDOW)..now)
      queued = 0
      sessions.find_each do |session|
        LlmCalls::Materializer.call(session)
        queued += 1 if Export.enqueue(session, send_now: false)
      end
      queued
    end
  end
end
