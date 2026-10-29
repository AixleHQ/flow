# frozen_string_literal: true

# A built-in agent runtime as config/agent_runtimes.json declares it. CI builds the
# images from the same file, so a runtime list kept anywhere else drifts from what
# was actually published.
AgentRuntime = Data.define(:id, :image, :cli_version, :reasoning_effort) do
  def self.all
    @all ||= JSON.parse(Rails.root.join("config/agent_runtimes.json").read).fetch("runtimes").map do |entry|
      new(id: entry.fetch("id"), image: entry.fetch("image"), cli_version: entry.fetch("cli_version"),
          reasoning_effort: entry["reasoning_effort"])
    end.freeze
  end

  def self.ids
    all.map(&:id)
  end

  def self.fetch(id)
    all.find { |runtime| runtime.id == id.to_s } || raise(KeyError, "unknown agent runtime: #{id}")
  end

  # Every effort level any runtime accepts for any model, for the places that store
  # one before the runtime is known.
  def self.reasoning_effort_levels
    @reasoning_effort_levels ||= all.flat_map do |runtime|
      spec = runtime.reasoning_effort || {}
      Array(spec["levels"]) + Array(spec["models"]).flat_map { |rule| Array(rule["levels"]) }
    end.uniq.freeze
  end

  # The reasoning-effort levels this runtime's CLI takes for `model` (nil: the CLI's
  # default model), in the registry's order. Empty when the CLI cannot set one for
  # that model: the registry's `reasoning_effort` field and
  # docs/architecture/agent-runtime-registry.md say how each CLI was checked.
  def reasoning_effort_levels(model = nil)
    spec = reasoning_effort
    return [] if spec.blank?
    return [] if spec["requires_model"] && model.blank?

    rule = model.present? && Array(spec["models"]).find { |entry| Regexp.new(entry.fetch("match")).match?(model.to_s) }
    Array(rule ? rule.fetch("levels") : spec.fetch("levels"))
  end

  def reasoning_effort?(level, model = nil)
    level.present? && reasoning_effort_levels(model).include?(level.to_s)
  end
end
