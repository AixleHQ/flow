# frozen_string_literal: true

module ContextBuilders
  class Tools < Base
    def build
      sections = []
      sections << shell_tools_section
      sections << mcp_servers_section if mcp_servers.any?
      sections << custom_tools_section if available_tools.any?
      sections
    end

    private

    def shell_tools_section
      section(
        tag: "shell-tools",
        priority: :info,
        content: build_shell_tools,
        position_hint: :bottom
      )
    end

    def mcp_servers_section
      section(
        tag: "mcp-servers",
        priority: :info,
        content: build_mcp_descriptions,
        position_hint: :bottom
      )
    end

    def custom_tools_section
      section(
        tag: "custom-tools",
        priority: :info,
        content: build_tool_descriptions,
        position_hint: :bottom
      )
    end

    def build_shell_tools
      <<~MD.strip
        ## Available Shell Tools

        The following command-line tools are pre-installed and available:

        | Tool | Description | Example |
        |------|-------------|---------|
        | `tree` | Display directory structure | `tree -d -L 2` (dirs only), `tree -L 3 /workspace/repo/` |
        | `cloc` | Count lines of code by language | `cloc .`, `cloc --by-file /workspace/repo/` |
        | `rg` | ripgrep — fast code search | `rg 'TODO' --type ruby`, `rg -l 'class.*Service'` |
        | `fd` | Fast file finder | `fd -e rb`, `fd -e tsx -x wc -l {}` |
        | `jq` | JSON processor | `jq '.dependencies' package.json` |
        | `git` | Version control | `git log --oneline -20`, `git diff` |
        | `curl` | HTTP requests | `curl -s https://api.example.com` |
      MD
    end

    def build_mcp_descriptions
      lines = [ "## Available MCP Servers" ]
      lines << ""

      # Always include aixle-tools
      lines << "### aixle-tools"
      lines << "Internal tools server. Provides project-specific tools configured for this session."
      lines << "Call tools via MCP — use `tools/list` to see available tools."
      lines << ""

      external_servers.each do |server|
        lines << "### #{server.name}"
        lines << server.description if server.description.present?
        lines << ""
      end

      lines.join("\n")
    end

    def build_tool_descriptions
      tools = available_tools
      has_container = tools.any? { |t| t.respond_to?(:execution_mode) && t.execution_mode.to_s == "container" }

      lines = [ "## Available Tools" ]
      lines << ""
      lines << "These tools are provided via the **aixle-tools** MCP server. Call them through MCP."
      lines << ""

      if has_container
        lines << tool_execution_modes_section
        lines << ""
      end

      tools.each do |tool|
        mode = tool.respond_to?(:execution_mode) ? tool.execution_mode.to_s : "app"
        marker = mode == "container" ? "⏳ container" : "⚡ app"
        lines << "### #{tool.name} #{marker}"
        desc = [ tool.display_name, tool.description ].compact.join(" — ")
        lines << desc if desc.present?
        lines << (mode == "container" ? "Returns: execution ID → use read_tool_result to get results" : "Returns: direct result")
        if tool.input_schema.present? && tool.input_schema["properties"].present?
          params = tool.input_schema["properties"].map { |k, v| "#{k} (#{v['type']})" }.join(", ")
          lines << "Parameters: #{params}" if params.present?
        end
        lines << ""
      end

      lines.join("\n")
    end

    def tool_execution_modes_section
      <<~MD.strip
        ### Tool Execution Modes

        Tools on this platform work in two modes:

        **Instant tools (⚡ app)** return results directly in the MCP response. Use them normally.

        **Container tools (⏳ container)** run in Docker containers and may take seconds to minutes. They work asynchronously:

        1. **Call the tool** — you receive an execution ID (e.g. `tr-a1b2c3d4e5f6`)
        2. **Check status** — call `read_tool_result(tool_result_id: "tr-...")`.
           If `state` is `processing`, wait and try again.
           If `state` is `completed` or `failed`, proceed to step 3.
        3. **Download results** — the response contains presigned URLs (`stdout_url`, `result_data_url`, etc.).
           Download them to local files:
           ```
           curl -sS -o /workspace/result.json "<result_data_url>"
           ```
        4. **Process locally** — read and analyze the downloaded files as needed.

        Important:
        - NEVER expect container tool output directly in the MCP response — you only get an ID.
        - Presigned URLs expire in 1 hour. Call `read_tool_result` again for fresh URLs if needed.
        - `result_data_url` contains parsed JSON (if the tool output was valid JSON). Prefer it over `stdout_url`.
        - `output_url` is a tar.gz archive of additional files collected from the tool container (if any).
      MD
    end

    def mcp_servers
      @mcp_servers ||= [ "aixle-tools" ] + external_servers.map(&:name)
    end

    def external_servers
      @external_servers ||= begin
        ids = session.mcp_server_ids
        ids.present? ? MCPServer.where(id: ids, enabled: true).to_a : []
      end
    end

    def available_tools
      @available_tools ||= session.available_tools.to_a
    end
  end
end
