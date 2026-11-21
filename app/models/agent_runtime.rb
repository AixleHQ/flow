# frozen_string_literal: true

# A built-in agent runtime as config/agent_runtimes.json declares it. CI builds the
# images from the same file, so a runtime list kept anywhere else drifts from what
# was actually published.
AgentRuntime = Data.define(:id, :label, :image, :cli_version, :reasoning_effort) do
  def self.all
    @all ||= JSON.parse(Rails.root.join("config/agent_runtimes.json").read).fetch("runtimes").map do |entry|
      new(id: entry.fetch("id"), label: entry.fetch("label"), image: entry.fetch("image"), cli_version: entry.fetch("cli_version"),
          reasoning_effort: entry["reasoning_effort"])
    end.freeze
  end

  def self.ids
    all.map(&:id)
  end

  def self.fetch(id)
    all.find { |runtime| runtime.id == id.to_s } || raise(KeyError, "unknown agent runtime: #{id}")
  end

  def self.label_for(id)
    all.find { |runtime| runtime.id == id.to_s }&.label || id.to_s.humanize
  end

  # Every effort level any runtime takes for any model, in order. The enum of the
  # create_workflow_step and update_workflow_step MCP tools, and the order every runtime's
  # levels are listed in; a step's level is checked against its own runtime's grammar.
  def self.reasoning_effort_levels
    @reasoning_effort_levels ||= all.flat_map do |runtime|
      spec = runtime.reasoning_effort || {}
      Array(spec["levels"]) + Array(spec["models"]).flat_map { |rule| Array(rule["levels"]) }
    end.uniq.freeze
  end

  # Every level this runtime's CLI takes for some model, in the registry's order: what
  # a step's or session's level is validated against (ReasoningEffortValidator). Empty for a
  # runtime whose model id carries the effort.
  def reasoning_effort_grammar
    spec = reasoning_effort || {}
    self.class.reasoning_effort_levels & (Array(spec["levels"]) + Array(spec["models"]).flat_map { |rule| Array(rule["levels"]) })
  end

  # The levels the model pickers offer for `model`. `offered` is what the vendor's
  # catalogue says that model takes (the adapter's model entry `reasoning_effort_levels`),
  # kept to the levels this CLI takes; without one, the registry's rule for the model
  # stands in. A level is set only on an explicitly chosen model, so a blank one has none.
  # docs/architecture/agent-runtime-registry.md says where each runtime's come from.
  def reasoning_effort_levels(model, offered: nil)
    spec = reasoning_effort
    return [] if spec.blank? || model.blank?
    return reasoning_effort_grammar & offered.map(&:to_s) if offered

    rule = Array(spec["models"]).find { |entry| Regexp.new(entry.fetch("match")).match?(model.to_s) }
    Array(rule ? rule.fetch("levels") : spec.fetch("levels"))
  end

  def reasoning_effort?(level)
    level.present? && reasoning_effort_grammar.include?(level.to_s)
  end
end
