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

  # Every effort level any runtime takes for any model. Only the enum of the
  # create_workflow_step and update_workflow_step MCP tools uses it: a step's level is
  # checked against its own runtime and model by reasoning_effort_levels(model).
  def self.reasoning_effort_levels
    @reasoning_effort_levels ||= all.flat_map do |runtime|
      spec = runtime.reasoning_effort || {}
      Array(spec["levels"]) + Array(spec["models"]).flat_map { |rule| Array(rule["levels"]) }
    end.uniq.freeze
  end

  # The reasoning-effort levels this runtime's CLI takes for `model`, in the
  # registry's order. A level is set only on an explicitly chosen model, so a blank
  # one has none. Empty too when the CLI cannot set one for that model: the
  # registry's `reasoning_effort` field and docs/architecture/agent-runtime-registry.md
  # say how each CLI was checked.
  def reasoning_effort_levels(model)
    spec = reasoning_effort
    return [] if spec.blank? || model.blank?

    rule = Array(spec["models"]).find { |entry| Regexp.new(entry.fetch("match")).match?(model.to_s) }
    Array(rule ? rule.fetch("levels") : spec.fetch("levels"))
  end

  def reasoning_effort?(level, model)
    level.present? && reasoning_effort_levels(model).include?(level.to_s)
  end
end
