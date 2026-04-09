# frozen_string_literal: true

# Executes internal tools by resolving the handler class and running it.
#
# Handler resolution: Tool name → InternalTools::{name.classify}
#   e.g. "list_sub_steps" → InternalTools::ListSubSteps
class InternalToolExecutor
  class << self
    # @param tool [Tool] internal tool record
    # @param params [Hash] tool call parameters
    # @param session [TerminalSession] current session
    # @return [Hash] { exit_code:, stdout:, stderr: }
    def execute(tool, params, session)
      validate_params!(tool, params)
      handler_class = resolve_handler(tool)
      handler = handler_class.new(params: params || {}, session: session)
      handler.execute
    rescue InternalTools::WorkflowContextError => e
      { exit_code: 1, stdout: "", stderr: e.message }
    rescue StandardError => e
      unless Rails.env.test?
        Rails.logger.error("[InternalToolExecutor] #{tool.name} failed: #{e.class} — #{e.message}")
      end
      { exit_code: 1, stdout: "", stderr: "Internal tool error: #{e.message}" }
    end

    private

    def resolve_handler(tool)
      class_name = "InternalTools::#{tool.name.camelize}"
      class_name.constantize
    rescue NameError
      raise ArgumentError, "No handler found for internal tool '#{tool.name}' (expected #{class_name})"
    end

    def validate_params!(tool, params)
      schema = tool.input_schema
      return if schema.blank?

      required = schema["required"] || schema[:required] || []
      return if required.empty?

      params_keys = (params || {}).keys.map(&:to_s)
      missing = required.map(&:to_s) - params_keys
      raise ArgumentError, "Missing required parameters: #{missing.join(', ')}" if missing.any?
    end
  end
end
