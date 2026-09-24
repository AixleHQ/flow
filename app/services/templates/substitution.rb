# frozen_string_literal: true

module Templates
  # `{{inputs.<key>}}` substitution. Only that exact pattern is touched, so a
  # tool's `{{param}}` placeholders and a trigger title's `{{date}}` survive the
  # install. Plain string replacement: no expressions, no conditionals.
  module Substitution
    PATTERN = /\{\{\s*inputs\.([a-z][a-z0-9_]*)\s*\}\}/

    # The fields an input may be substituted into, as paths through the
    # definition ("*" = every array element or hash value). Anything outside
    # this list is installed verbatim, and the validator rejects a placeholder
    # there, so the substitution surface stays reviewable.
    ALLOWED_PATHS = [
      %w[project description],
      %w[board columns * purpose],
      %w[agents * persona], %w[agents * principles], %w[agents * communication_style],
      %w[workflows * description],
      %w[workflows * steps * instructions],
      %w[workflows * steps * sub_steps * instructions],
      %w[mcp_servers * custom url], %w[mcp_servers * custom args *],
      %w[mcp_servers * custom headers *], %w[mcp_servers * custom env *],
      %w[triggers * cron], %w[triggers * subject_title_template],
      %w[variables * value]
    ].freeze

    module_function

    def apply(value, inputs)
      return value unless value.is_a?(String)

      value.gsub(PATTERN) { inputs.fetch(Regexp.last_match(1)) { "" }.to_s }
    end

    def keys_in(value)
      value.is_a?(String) ? value.scan(PATTERN).flatten : []
    end

    def allowed?(path)
      ALLOWED_PATHS.any? do |pattern|
        pattern.length == path.length && pattern.zip(path).all? { |want, got| want == "*" || want == got.to_s }
      end
    end

    # Yields every string in the definition with its path, e.g.
    # ["workflows", 0, "steps", 1, "instructions"].
    def each_string(node, path = [], &block)
      case node
      when Hash then node.each { |key, child| each_string(child, path + [ key.to_s ], &block) }
      when Array then node.each_with_index { |child, index| each_string(child, path + [ index ], &block) }
      when String then yield node, path
      end
    end
  end
end
