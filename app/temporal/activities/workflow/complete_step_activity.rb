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

        # `cancelled`, not only `failed`: every watchdog reaches a session through
        # SessionService.fail_session, which for an admitted session cancels instead of
        # failing (the reservation is only released once the runtime is confirmed gone).
        # Treating cancelled as "not a failure" is what let a killed session fall through
        # to mark_completed! — 53 step runs in the 14 days to 2026-09-17 completed on a
        # session that had been cancelled or failed.
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

      def detect_quota_error(session)
        return QuotaErrorDetector.detect(nil) unless session

        QuotaErrorDetector.detect(quota_detection_text(session))
      end

      # An expired login is silent: the CLI prints its banner, renders a prompt nobody
      # answers, and the step would otherwise be judged only on the absence of output.
      # Same text as the quota check, which is already read and ANSI-stripped.
      def detect_auth_error(session)
        return AuthErrorDetector.detect(nil) unless session

        AuthErrorDetector.detect(quota_detection_text(session))
      end

      def quota_detection_text(session)
        parts = [ session.error_message ]
        log = session.session_logs.find_by(name: "terminal_output.log")
        # The terminal log now carries raw ANSI escape sequences (see
        # AgentSessionStrategy#start_terminal_capture). Strip them so quota-error
        # patterns still match on the plain text.
        parts << strip_ansi(log.file.read) if log&.file
        parts.compact_blank.join("\n")
      rescue StandardError => e
        Rails.logger.warn("[CompleteStepActivity] Failed to read terminal log: #{e.message}")
        session.error_message.to_s
      end

      # The terminal log is now the raw PTY stream (see AgentSessionStrategy#collect_terminal_output),
      # so strip the full family of escape sequences a redrawing TUI emits — CSI (colors/cursor),
      # OSC (window title), and the 2-char charset/other escapes — before quota matching. Carriage
      # returns (in-place redraws) become newlines so overwritten phrases still match.
      ANSI_CSI = /\e\[[0-9;?]*[ -\/]*[@-~]/
      ANSI_OSC = /\e\][^\a\e]*(?:\a|\e\\)/
      ANSI_OTHER = /\e[@-Z\\-_()][0-9A-Za-z]?/

      def strip_ansi(text)
        text.to_s
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

      def validate_outputs(step_run, assets)
        OutputValidator.new(step_run.step, assets).validate!
      rescue StandardError => e
        Rails.logger.error("[CompleteStepActivity] Output validation failed: #{e.message}")
        OutputValidator::Result.new(valid?: true, errors: [])
      end
    end
  end
end
