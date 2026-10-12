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
        content: build_tool_index,
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
      lines << "Internal tools server: the platform tools listed under Available Tools."
      lines << ""

      external_servers.each do |server|
        lines << "### #{server.name}"
        lines << server.description if server.description.present?
        lines << ""
      end

      lines.join("\n")
    end

    # Names only: every runtime receives each tool's description and parameters from
    # the MCP server itself, so repeating them here cost tokens on every model call.
    def build_tool_index
      container, instant = available_tools.partition { |tool| container_tool?(tool) }

      lines = [ "## Available Tools" ]
      lines << ""
      lines << "Provided by the **aixle-tools** MCP server:"
      lines << ""
      lines << instant.map { |tool| "`#{tool.name}`" }.join(", ") if instant.any?

      if container.any?
        lines << ""
        lines << tool_execution_modes_section
        lines << ""
        lines << "Container tools: #{container.map { |tool| "`#{tool.name}`" }.join(', ')}"
      end

      lines.join("\n")
    end

    def container_tool?(tool)
      tool.respond_to?(:execution_mode) && tool.execution_mode.to_s == "container"
    end

    def tool_execution_modes_section
      <<~MD.strip
        ### Tool Execution Modes

        Tools on this platform work in two modes:

        **Instant tools** return results directly in the MCP response. Use them normally.

        **Container tools** (listed below) run in Docker containers and may take seconds to minutes. They work asynchronously:

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
