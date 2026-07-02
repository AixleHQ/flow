# frozen_string_literal: true

module Tools
  # In-process registry of code-defined platform tools, discovered from
  # InternalTools::Base descendants that declare a `tool do ... end` block.
  #
  # Zeitwerk-safe by construction: the memo holds only frozen Definition POROs
  # (data + class-name strings, never class objects), and is dropped on every
  # code reload via to_prepare (config/initializers/tools_registry.rb). See the
  # registry research report — this is the maintenance_tasks discovery pattern,
  # deliberately NOT actionmcp's process-global ToolsRegistry (non-thread-safe,
  # wiped on dev reload).
  module Registry
    class DuplicateToolError < StandardError; end

    class << self
      def definitions
        # Benign race under Puma threads: concurrent builders produce
        # identical frozen values.
        @definitions || build
      end

      def fetch(name)
        definitions[name.to_s]
      end

      def names
        definitions.keys
      end

      def tagged(tag)
        definitions.values.select { |d| d.tags.include?(tag.to_sym) }
      end

      def injectable
        definitions.values.reject { |d| d.inject_rules.empty? }
      end

      def for_audience(audience)
        definitions.values.select { |d| d.audience == audience.to_sym }
      end

      def managed_tool_names(provider)
        return [] if provider.blank?

        definitions.values
                   .select { |d| d.managed_mcp_provider.to_s == provider.to_s }
                   .map(&:name)
      end

      def reset!
        @definitions = nil
      end

      private

      def build
        unless Rails.application.config.eager_load
          Rails.autoloaders.main.eager_load_namespace(InternalTools)
          Rails.autoloaders.main.eager_load_namespace(PersonalTools)
        end

        defs = (InternalTools::Base.descendants + PersonalTools::Base.descendants)
               .select(&:tool_defined?).map(&:tool_definition)
        duplicates = defs.group_by(&:name).select { |_, group| group.size > 1 }.keys
        raise DuplicateToolError, "Duplicate tool definitions: #{duplicates.join(', ')}" if duplicates.any?

        @definitions = defs.sort_by(&:name).index_by(&:name).freeze
      end
    end
  end
end
