# frozen_string_literal: true

# A built-in agent runtime as config/agent_runtimes.json declares it. CI builds the
# images from the same file, so a runtime list kept anywhere else drifts from what
# was actually published.
AgentRuntime = Data.define(:id, :image, :cli_version) do
  def self.all
    @all ||= JSON.parse(Rails.root.join("config/agent_runtimes.json").read).fetch("runtimes").map do |entry|
      new(id: entry.fetch("id"), image: entry.fetch("image"), cli_version: entry.fetch("cli_version"))
    end.freeze
  end

  def self.ids
    all.map(&:id)
  end

  def self.fetch(id)
    all.find { |runtime| runtime.id == id.to_s } || raise(KeyError, "unknown agent runtime: #{id}")
  end
end
