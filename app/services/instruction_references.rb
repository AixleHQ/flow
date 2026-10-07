# frozen_string_literal: true

# `@` references in a session's instructions (docs/design/at-references.md).
# The text stays plain; a reference is a token carrying a stable id:
#
#   {{asset:123}}               an Asset
#   {{output:45:summary.md}}    output spec "summary.md" of step 45
#   {{step:45}}                 step 45 of the same workflow
#   {{mcp:7}}                   an MCPServer
#
# A step is named by id, or by the builder's `new-<n>` key while it is unsaved
# (WorkflowStepSync rewrites those on save). Template packages carry package
# keys in the same positions; Templates::Exporter and Installer translate them.
module InstructionReferences
  SCANNER = /\{\{(asset|output|step|mcp):([^{}\n]+?)\}\}/
  BRACES = /\{\{[^{}\n]*\}\}/
  STEP_KEY = /\A(?:[1-9]\d*|new-[1-9]\d*)\z/
  ID = /\A[1-9]\d*\z/

  # `id` is an Integer for assets and servers, a step key String for steps and
  # outputs, and nil when the body does not parse.
  Ref = Data.define(:type, :id, :name, :text) do
    def valid? = !id.nil?
  end

  module_function

  def scan(text)
    text.to_s.to_enum(:scan, SCANNER).map do
      match = Regexp.last_match
      parse(match[1], match[2], match[0])
    end
  end

  # Replaces each reference with the block's result; nil keeps the token.
  def rewrite(text)
    rewrite_tokens(text) { |type, body, token| yield parse(type, body, token) }
  end

  # #rewrite over the raw `type` and `body`, for template packages, whose
  # tokens carry package keys where a saved workflow carries ids.
  def rewrite_tokens(text)
    return text if text.blank?

    text.gsub(SCANNER) do
      match = Regexp.last_match
      yield(match[1], match[2], match[0]) || match[0]
    end
  end

  # `{{…}}` the runtime will hand over verbatim: not a reference, and nothing
  # else substitutes it during a run.
  def unknown_braces(text)
    text.to_s.scan(BRACES).reject { |braces| braces.match?(/\A#{SCANNER}\z/o) }.uniq
  end

  def ids(text, type)
    scan(text).select { |ref| ref.type == type && ref.valid? }.map(&:id).uniq
  end

  def parse(type, body, token)
    id, name = case type
    when "asset", "mcp" then [ (body.to_i if body.match?(ID)), nil ]
    when "step" then [ (body if body.match?(STEP_KEY)), nil ]
    when "output"
      key, file = body.split(":", 2)
      key.to_s.match?(STEP_KEY) && file.present? ? [ key, file ] : [ nil, nil ]
    end
    Ref.new(type: type, id: id, name: name, text: token)
  end
end
