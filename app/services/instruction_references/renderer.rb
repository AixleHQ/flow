# frozen_string_literal: true

module InstructionReferences
  # Replaces each reference in a step's instructions with what the agent can act
  # on — a container path or a name — read from live rows at launch.
  #
  # Every lookup is scoped: assets, servers, tools, skills and config items the
  # project can reach, steps of the step's own workflow. A config item is named,
  # never read: its value reaches the agent only through `get_config_item`. An id outside those scopes renders as a
  # missing reference instead of naming another tenant's row.
  class Renderer
    def initialize(step:, project:)
      @step = step
      @project = project
    end

    def render(text)
      refs = InstructionReferences.scan(text)
      return text if refs.empty?

      load(refs)
      InstructionReferences.rewrite(text) { |ref| replacement(ref) }
    end

    private

    def load(refs)
      ids = ->(type) { refs.select { |ref| ref.type == type && ref.valid? }.map(&:id).uniq }
      @assets = @project ? Asset.accessible_from_project(@project).where(id: ids.call("asset")).index_by(&:id) : {}
      @servers = @project ? MCPServer.visible_for_project(@project).where(id: ids.call("mcp")).index_by(&:id) : {}
      @tools = @project ? Tool.visible_for_project(@project).where(id: ids.call("tool")).index_by(&:id) : {}
      @skills = @project ? Skill.visible_for_project(@project).where(id: ids.call("skill")).index_by(&:id) : {}
      @config_items = @project ? ConfigItem.visible_for_project(@project).where(id: ids.call("config_item")).index_by(&:id) : {}
      @steps = @step.workflow.steps.not_deleted.index_by { |step| step.id.to_s }
    end

    def replacement(ref)
      return missing(ref) unless ref.valid?

      case ref.type
      when "asset" then (asset = @assets[ref.id]) ? "`#{asset_path(asset)}`" : missing(ref)
      when "mcp" then (server = @servers[ref.id]) ? %(the "#{server.name}" MCP server) : missing(ref)
      when "step" then (step = @steps[ref.id]) ? %(session "#{step.name}") : missing(ref)
      when "output" then output_path(ref)
      when "tool" then (tool = @tools[ref.id]) ? "the `#{tool.name}` tool" : missing(ref)
      when "skill" then (skill = @skills[ref.id]) ? skill_name(skill) : missing(ref)
      when "config_item"
        (item = @config_items[ref.id]) ? "the `#{item.name}` config item (read it with `get_config_item`)" : missing(ref)
      end
    end

    # A runtime that installs skills as files finds one by its name; the
    # context file lists it by title.
    def skill_name(skill)
      title = skill.title.presence
      title && title != skill.name ? %(the "#{title}" skill (`#{skill.name}`)) : "the `#{skill.name}` skill"
    end

    # The producing step writes the file; every later step finds the copy
    # WorkflowStepStrategy#inject_prior_step_outputs put in its assets.
    def output_path(ref)
      producer = @steps[ref.id]
      name = DataFlow::AssetSpec.normalize_name(ref.name)
      return missing(ref) unless producer&.output_specs&.any? { |spec| spec.plain? && spec.name == name }

      dir = producer.id == @step.id ? "/workspace/outputs" : Asset::CONTAINER_DIR
      "`#{dir}/#{name}`"
    end

    def asset_path(asset)
      "#{Asset::CONTAINER_DIR}/#{[ asset.folder.presence, asset.name ].compact.join('/')}"
    end

    def missing(ref) = "[missing reference: #{ref.text.delete('{}')}]"
  end
end
