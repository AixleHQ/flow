# frozen_string_literal: true

module ProjectResources
  # Creates project-scoped agents, skills, tools and MCP servers from plain
  # attribute hashes, with an explicit allow-list of what each carries. Used by
  # Templates::Installer, which reads the attributes out of a template package.
  class Builder
    AGENT_ATTRIBUTES = %i[name title icon persona communication_style principles source].freeze
    SKILL_ATTRIBUTES = %i[name title description package source source_url content content_hash files origin].freeze
    TOOL_ATTRIBUTES = %i[name display_name description docker_image command execution_mode input_schema
                         required_config_items enabled requires_integration].freeze
    MCP_SERVER_ATTRIBUTES = %i[name url transport description command args enabled env headers auth_type
                               credential_scope connector_name connector_version connector_manifest].freeze

    def initialize(project)
      @project = project
    end

    def agent!(attributes)
      @project.agents.create!(attributes.to_h.symbolize_keys.slice(*AGENT_ATTRIBUTES))
    end

    def skill!(attributes)
      Skill.create!(attributes.to_h.symbolize_keys.slice(*SKILL_ATTRIBUTES).merge(scope: @project, install_count: 0))
    end

    # @param files [Array<Hash>] `{ path:, content: }` for text files; add
    #   `file:` (an uploaded file or IO) for a binary one, stored as a new object
    #   of this tool's own.
    def tool!(attributes, files: [])
      tool = Tool.create!(attributes.to_h.symbolize_keys.slice(*TOOL_ATTRIBUTES).merge(scope: @project))
      files.each do |file|
        file = file.to_h.symbolize_keys
        copy = tool.tool_files.build(file.slice(:path, :content))
        copy.file_attacher.attach(file[:file]) if file[:file]
        copy.save!
      end
      tool
    end

    def mcp_server!(attributes)
      MCPServer.create!(attributes.to_h.symbolize_keys.slice(*MCP_SERVER_ATTRIBUTES).merge(scope: @project))
    end
  end
end
