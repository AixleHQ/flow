# frozen_string_literal: true

module Tools
  # Class-level DSL for declaring a platform tool on its handler class:
  #
  #   module InternalTools
  #     class SlackPostMessage < Base
  #       tool do
  #         display_name "Slack Post Message"
  #         description  "Send a Slack message from this workflow..."
  #         tags         :messaging, :slack
  #         inject_when  :workflow_step_session
  #         requires_integration :slack
  #         param :text, type: :string, description: "Message text."
  #       end
  #     end
  #   end
  #
  # Writing the class IS the registration — Tools::Registry discovers every
  # InternalTools::Base descendant with a tool block. There is no seed file
  # and no registration call to forget.
  module DefinitionDSL
    def tool(&block)
      builder = Builder.new(default_tool_name)
      builder.instance_eval(&block)
      @tool_config = builder.to_h.merge(handler_class_name: name)
    end

    def tool_defined?
      instance_variable_defined?(:@tool_config) && @tool_config
    end

    def tool_definition
      Definition.new(**@tool_config)
    end

    # Inverse of InternalToolExecutor's name.camelize convention.
    def default_tool_name
      name.demodulize.underscore
    end

    class Builder
      def initialize(name)
        @h = {
          name: name,
          tags: [],
          inject_rules: [],
          audience: :session,
          user_attachable: true,
          input_schema: { "type" => "object", "properties" => {}, "required" => [] }
        }
      end

      def name(value) = @h[:name] = value.to_s
      def display_name(value) = @h[:display_name] = value
      def description(value) = @h[:description] = value
      def tags(*values) = @h[:tags] = values

      def inject_when(*rules)
        unknown = rules.map(&:to_sym) - InjectionRules::RULES.keys
        raise ArgumentError, "Unknown injection rule(s): #{unknown.join(', ')}" if unknown.any?

        @h[:inject_rules] = rules
      end

      def requires_integration(provider) = @h[:requires_integration] = provider

      # :session (default) — served inside terminal sessions, materialized as
      # a shadow row. :user — served only by the personal (token) MCP server,
      # never materialized, never injected, never in pickers.
      def audience(value) = @h[:audience] = value.to_sym

      # Escape hatch for availability conditions beyond integration presence;
      # AND-ed after the requires_integration check.
      def availability(callable = nil, &block) = @h[:availability] = callable || block

      def unavailable_message(value) = @h[:unavailable_message] = value
      def user_attachable(value) = @h[:user_attachable] = value
      def managed_mcp_provider(provider) = @h[:managed_mcp_provider] = provider

      # MCP behavior annotations (spec 2025-03-26+): serialized on the wire so
      # clients can drive confirmation policies. Untrusted display hints by
      # spec — never a security control.
      def read_only(value = true) = annotations["readOnlyHint"] = value
      def destructive(value = true) = annotations["destructiveHint"] = value
      def idempotent(value = true) = annotations["idempotentHint"] = value
      def open_world(value = true) = annotations["openWorldHint"] = value

      def annotations = @h[:annotations] ||= {}

      # Raw JSON-Schema hash, used verbatim (normalized to the JSON type
      # system — symbol keys and values become strings). For simple shapes
      # prefer the param sugar below.
      def input_schema(schema) = @h[:input_schema] = schema.as_json

      # Sugar compiling to JSON Schema:
      #   param :status, type: :string, enum: %w[open closed], required: true
      def param(param_name, type:, description: nil, required: false, enum: nil, items: nil, default: nil)
        prop = { "type" => type.to_s }
        prop["description"] = description if description
        prop["enum"] = enum if enum
        prop["items"] = items.deep_stringify_keys if items
        prop["default"] = default unless default.nil?

        @h[:input_schema]["properties"][param_name.to_s] = prop
        @h[:input_schema]["required"] << param_name.to_s if required
        prop
      end

      def to_h = @h
    end
  end
end
