# frozen_string_literal: true

module Activities
  module Workflow
    class CompleteStepActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        session = step_run.terminal_session

        detection = detect_quota_error(session)
        if detection.quota_error?
          return quota_failure_result(step_run, session, detection)
        end

        # `cancelled`, not only `failed`: a session stopped out from under its step
        # must never read as done. Treating cancelled as "not a failure" is what let a
        # killed session fall through to mark_completed! — 53 step runs in the 14 days
        # to 2026-09-17 completed on a session that had been cancelled or failed.
        if session && %w[failed cancelled].include?(session.state)
          # Why it ended matters as much as that it did: an expired login is a banner in
          # the terminal and nothing else, so without this the step reports "no output for
          # 30 minutes" for what is really "this agent needs signing in again".
          #
          # Read only on a session that already ended badly. An agent that merely printed
          # the words — editing auth code, quoting a CLI's help — must never turn a
          # finished run into a failed one.
          auth = detect_auth_error(session)
          return auth_failure_result(step_run, auth) if auth.auth_error?

          step_run.mark_failed!(session.error_message.presence || "Session #{session.state}")
          return { "step_run_id" => step_run.id, "valid" => false, "failed" => true }
        end

        if step_run.error_message.present?
          step_run.mark_failed!(step_run.error_message)
          return { "step_run_id" => step_run.id, "valid" => false, "failed" => true }
        end

        assets = collected_assets(step_run)
        validation = validate_outputs(step_run, assets)

        unless validation.valid?
          step_run.mark_failed!("Output validation failed: #{validation.errors.join(', ')}")
          return {
            "step_run_id" => step_run.id,
            "validation_errors" => validation.errors,
            "valid" => false,
            "failed" => true
          }
        end

        step_run.mark_completed!

        {
          "step_run_id" => step_run.id,
          "step_id" => step_run.step_id,
          "workflow_run_id" => step_run.workflow_run_id,
          "assets_collected" => assets.size,
          "valid" => true
        }
      end

      private

      # A real stop leaves the session's own CLI's message either in error_message (the
      # quota scan failed the session with it) or as the last thing in its terminal log
      # (a CLI that exits by itself on quota, as Kiro does). The rest of the log is the
      # agent's work, which can print the very text these patterns look for: task #195,
      # where runs that survived the scan were still failed here, and their healthy
      # credential flagged, because of a grep earlier in the session. So the log is read
      # the way Sessions::LogTail reads a stored log: own provider, tail only.
      #
      # A session whose finish was requested is not read at all. An agent that called
      # finish_session reported success itself, which a CLI its provider refused cannot
      # do, and its log's tail is its own closing summary, free to name these
      # identifiers. A person's stop is a requested end, not a provider refusal. A CLI
      # that exits by itself on its provider's refusal never goes through finishing, so
      # finishing_at stays nil and its log is still read.
      def detect_quota_error(session)
        return QuotaErrorDetector.detect(nil) unless session

        recorded = QuotaErrorDetector.detect(session.error_message, agent_type: session.agent_type)
        return recorded if recorded.quota_error?
        return QuotaErrorDetector.detect(nil) if finish_requested?(session)

        QuotaErrorDetector.detect_on_screen(terminal_log_text(session), agent_type: session.agent_type)
      end

      # Ended through `finishing`, which stamps finishing_at before the session ends
      # `finished`: SessionService.finish (the agent's finish_session, or a person's
      # stop through the API, the personal tools or the builder) and the stale-session
      # cleanup (CleanupStaleActivity#full_cleanup). AdmittedPhaseActivity#outcome_state
      # and #outcome_error read finishing_at the same way, as a requested finish.
      def finish_requested?(session)
        session.state == "finished" && session.finishing_at.present?
      end

      # An expired login is silent: the CLI prints its banner, renders a prompt nobody
      # answers, and the step would otherwise be judged only on the absence of output.
      # The error message and the whole ANSI-stripped log: this runs only on a session
      # that already ended badly (see #execute).
      def detect_auth_error(session)
        return AuthErrorDetector.detect(nil) unless session

        AuthErrorDetector.detect(auth_detection_text(session))
      end

      def auth_detection_text(session)
        [ session.error_message, terminal_log_text(session) ].compact_blank.join("\n")
      end

      def terminal_log_text(session)
        log = session.session_logs.find_by(name: "terminal_output.log")
        # The terminal log now carries raw ANSI escape sequences (see
        # AgentSessionStrategy#start_terminal_capture). Strip them so quota-error
        # patterns still match on the plain text.
        log&.file ? strip_ansi(log.file.read) : ""
      rescue StandardError => e
        Rails.logger.warn("[CompleteStepActivity] Failed to read terminal log: #{e.message}")
        ""
      end

      # The terminal log is now the raw PTY stream (see AgentSessionStrategy#collect_terminal_output),
      # so strip the full family of escape sequences a redrawing TUI emits — CSI (colors/cursor),
      # OSC (window title), and the 2-char charset/other escapes — before quota matching. Carriage
      # returns (in-place redraws) become newlines so overwritten phrases still match.
      #
      # Shrine opens the stored file in binary mode, so the bytes arrive as ASCII-8BIT.
      # A pattern that is not pure ASCII cannot match that: AuthErrorDetector's "·"
      # is a UTF-8 regexp, and String#match? raises Encoding::CompatibilityError as
      # soon as the log holds a byte >= 128. Scrub, because a PTY stream is not
      # guaranteed to be valid UTF-8 either — an invalid sequence would raise
      # ArgumentError out of the same match.
      ANSI_CSI = /\e\[[0-9;?]*[ -\/]*[@-~]/
      ANSI_OSC = /\e\][^\a\e]*(?:\a|\e\\)/
      ANSI_OTHER = /\e[@-Z\\-_()][0-9A-Za-z]?/

      def strip_ansi(text)
        text.to_s.dup
            .force_encoding(Encoding::UTF_8)
            .scrub
            .gsub(ANSI_OSC, "")
            .gsub(ANSI_CSI, "")
            .gsub(ANSI_OTHER, "")
            .tr("\r", "\n")
      end

      def quota_failure_result(step_run, session, detection)
        # The credential that hit the quota is the one this session ran on: its company's.
        credential = SessionCompany.agent_credentials_for(session).find_by(agent_type: session&.agent_type)
        step_run.mark_failed!(detection.message, error_category: :quota_exceeded)
        step_run.workflow_run.mark_quota_failed!(credential_id: credential&.id)
        {
          "step_run_id" => step_run.id,
          "valid" => false,
          "failed" => true,
          "quota_error" => true
        }
      end

      # No workflow-level side effect (unlike quota, which pauses the run against the
      # offending credential): the credential the step ran on may already have been
      # re-authenticated by the time this lands, and the refresh sweep owns that verdict.
      # What matters here is that the step says why it failed.
      def auth_failure_result(step_run, detection)
        step_run.mark_failed!("Agent authentication failed: #{detection.message}", error_category: :auth_expired)
        { "step_run_id" => step_run.id, "valid" => false, "failed" => true, "auth_error" => true }
      end

      def collected_assets(step_run)
        step_run.produced_workflow_run_assets.reload.to_a
      end

      # A validator that crashed has not judged this step, and answering "valid" on its
      # behalf is how a step that produced nothing at all still reported success. Fail it
      # with the crash as the reason: an unjudged step is not a passed one.
      def validate_outputs(step_run, assets)
        OutputValidator.new(step_run.step, assets).validate!
      rescue StandardError => e
        Rails.logger.error("[CompleteStepActivity] Output validation crashed: #{e.class}: #{e.message}")
        OutputValidator::Result.new(valid?: false, errors: [ "output validation could not run: #{e.message}" ])
      end
    end
  end
end
