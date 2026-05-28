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
        parts << log.file.read if log&.file
        parts.compact_blank.join("\n")
      rescue StandardError => e
        Rails.logger.warn("[CompleteStepActivity] Failed to read terminal log: #{e.message}")
        session.error_message.to_s
      end

      def quota_failure_result(step_run, session, detection)
        credential = session&.user&.agent_credentials&.find_by(agent_type: session.agent_type)
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
