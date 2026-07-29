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

        if session&.state == "failed"
          step_run.mark_failed!(session.error_message.presence || "Session failed")
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
