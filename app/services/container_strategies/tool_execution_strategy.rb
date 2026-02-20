# frozen_string_literal: true

require "base64"
require "shellwords"
require "timeout"

module ContainerStrategies
  # ToolExecutionStrategy
  # Strategy for executing custom tools in Docker containers
  #
  # Key design: tool command runs as the container's main process (not via exec).
  # Container exits naturally when command finishes — no orphaned sleep containers.
  #
  # File injection is embedded directly into CMD: the container creates tool files
  # (via base64 decode) then runs the actual command. This is more reliable than
  # Docker archive API on created containers.
  #
  # Lifecycle phases:
  #   - before_create: Resolve image, build env vars from config items + project context
  #   - create: Create container with resource limits, CMD = file setup + tool command
  #   - start: Start container (files are created, then command runs immediately)
  #   - exec: Wait for container to exit, collect stdout/stderr from logs
  #   - before_cleanup: Collect output artifacts via archive API (works on exited container)
  #   - cleanup: Remove exited container
  #
  # Input:
  #   - tool: Tool model instance
  #   - parameters: Hash of command parameters
  #   - project: Project model instance (optional, for config resolution + context)
  #   - timeout: Execution timeout in seconds (optional, default 300)
  #
  class ToolExecutionStrategy < BaseStrategy
    DEFAULT_TIMEOUT = 300      # 5 minutes
    MAX_TIMEOUT = 1800         # 30 minutes
    MAX_OUTPUT_SIZE = 10.megabytes
    TIMEOUT_EXIT_CODE = 124    # Standard timeout exit code

    # == Lifecycle: before_create ==

    def before_create(context)
      tool = input[:tool]
      raise ArgumentError, "Tool must be custom" unless tool.custom?
      raise ArgumentError, "Tool requires docker_image" if tool.docker_image.blank?

      super(context)
    end

    # == Template Methods ==

    def resolve_image
      input[:tool].docker_image
    end

    def build_env_vars
      env_hash = {}

      # 1. MCP tool parameters (lowest priority)
      parameters = input[:parameters] || {}
      parameters.each do |key, value|
        env_name = key.to_s.upcase.gsub(/[^A-Z0-9_]/, "_")
        env_hash[env_name] = value.to_s
      end

      # 2. Config items override parameters (secrets take precedence)
      env_hash.merge!(resolve_config_items)

      # 3. Project context
      project = input[:project]
      if project
        env_hash["PALAD_PROJECT_ID"] = project.id.to_s
        env_hash["PALAD_PROJECT_NAME"] = project.name
      end

      env_hash.map { |k, v| "#{k}=#{v}" }
    end

    def build_labels
      tool = input[:tool]
      {
        "palad.type" => "tool_execution",
        "palad.tool_id" => tool.id.to_s,
        "palad.tool_name" => tool.name
      }
    end

    def build_host_config
      build_host_config_with_limits
    end

    def build_cmd
      tool = input[:tool]
      parameters = input[:parameters] || {}
      command = build_command(tool, parameters)

      if tool.tool_files.any?
        setup = tool.tool_files.map { |tf| file_setup_command(tf) }
        full_command = (setup + [ command ]).join(" && ")
        [ "/bin/sh", "-c", full_command ]
      else
        [ "/bin/sh", "-c", command ]
      end
    end

    def build_working_dir
      "/workspace"
    end

    def timeout_for(phase)
      return nil unless phase == :exec

      requested = input[:timeout] || DEFAULT_TIMEOUT
      [ requested.to_i, MAX_TIMEOUT ].min
    end

    # == Lifecycle: start ==
    # Start container — command begins executing immediately, skip health check

    def start(context)
      target = context[:container] || context[:container_id]
      context[:container] = runtime.start_container(target)
      context[:container_id] ||= runtime_container_id(context[:container] || target)
      # Tool containers run command directly and may exit quickly — skip health check
    end

    # == Lifecycle: exec ==
    # Wait for container to exit and collect output from logs

    def exec(context)
      container = context[:container]
      start_time = Time.current

      begin
        wait_result = runtime.wait_container(container)
        exit_code = wait_result["StatusCode"] || wait_result[:StatusCode] || -1

        logs = runtime.container_logs(container)
        duration_ms = ((Time.current - start_time) * 1000).to_i

        context[:result] = {
          exit_code: exit_code,
          stdout: truncate_output(logs[:stdout]),
          stderr: truncate_output(logs[:stderr]),
          duration_ms: duration_ms,
          timed_out: false
        }

        Rails.logger.info("[ToolExecution] Completed: exit_code=#{exit_code}, duration=#{duration_ms}ms")
      rescue Timeout::Error
        handle_execution_timeout(context, start_time, timeout_for(:exec))
      end
    end

    # == Lifecycle: before_cleanup ==
    # Collect output artifacts from exited container via archive API

    def before_cleanup(context)
      tool = input[:tool]
      return unless tool.respond_to?(:output_paths) && tool.output_paths.present?

      container = context[:container]
      output_files = {}

      tool.output_paths.each do |path|
        content = runtime.read_file(container, path)
        output_files[path] = content if content.present?
      rescue StandardError => e
        Rails.logger.warn("[ToolExecution] Failed to extract #{path}: #{e.message}")
      end

      context[:result] ||= {}
      context[:result][:output_files_count] = output_files.size
      context[:result][:output_files_paths] = output_files.keys
      Rails.logger.info("[ToolExecution] Collected #{output_files.size} output files")
    end

    private

    # Resolve config items to environment variables
    # Priority: Project level > Company level
    #
    # @return [Hash] ENV_NAME => value
    def resolve_config_items
      tool = input[:tool]
      project = input[:project]

      return {} if tool.required_config_items.blank?

      env_vars = {}
      company = project&.company || tool.scope

      tool.required_config_items.each do |name|
        config_item = find_config_item(name, project, company)
        next unless config_item

        env_name = name.upcase.gsub(/[^A-Z0-9_]/, "_")
        env_vars[env_name] = config_item.decrypted_value
      end

      env_vars
    end

    # Find config item with priority: Project > Company
    #
    # @param name [String] Config item name
    # @param project [Project, nil] Project context
    # @param company [Company] Company context
    # @return [ConfigItem, nil]
    def find_config_item(name, project, company)
      if project
        ConfigItem.find_by(name: name, scope: project) ||
          ConfigItem.find_by(name: name, scope: company)
      else
        ConfigItem.find_by(name: name, scope: company)
      end
    end

    # Build shell command to create a tool file inside container via base64 decode
    # Used in CMD to inject files before running the tool command
    #
    # @param tool_file [ToolFile] File to create
    # @return [String] Shell command string
    def file_setup_command(tool_file)
      dir = Shellwords.escape(File.dirname(tool_file.path))
      path = Shellwords.escape(tool_file.path)
      encoded = Base64.strict_encode64(tool_file.content || "")
      "mkdir -p #{dir} && echo '#{encoded}' | base64 -d > #{path}"
    end

    # Build command from tool definition and parameters
    # Replaces {{param}} placeholders with parameter values
    #
    # @param tool [Tool] Tool instance
    # @param parameters [Hash] Parameter values
    # @return [String] Resolved command
    def build_command(tool, parameters)
      command = tool.command.presence || "/bin/sh"

      parameters.each do |key, value|
        command = command.gsub("{{#{key}}}", value.to_s)
      end

      command
    end

    # Handle execution timeout — kill container and collect partial output
    #
    # @param context [Hash] Execution context
    # @param start_time [Time] Execution start time
    # @param timeout [Integer] Timeout that was exceeded
    def handle_execution_timeout(context, start_time, timeout)
      duration_ms = ((Time.current - start_time) * 1000).to_i

      begin
        context[:container].kill
      rescue StandardError
        nil
      end

      # Collect partial output from killed container
      logs = begin
        runtime.container_logs(context[:container])
      rescue StandardError
        { stdout: "", stderr: "" }
      end

      context[:result] = {
        exit_code: TIMEOUT_EXIT_CODE,
        stdout: truncate_output(logs[:stdout]),
        stderr: "Tool execution timed out after #{timeout} seconds\n#{truncate_output(logs[:stderr])}",
        duration_ms: duration_ms,
        timed_out: true
      }

      Rails.logger.warn("[ToolExecution] TIMEOUT after #{timeout}s")
    end

    # Truncate output to prevent memory issues
    #
    # @param output [String, nil] Output to truncate
    # @return [String] Truncated output
    def truncate_output(output)
      return "" if output.nil?
      return output if output.bytesize <= MAX_OUTPUT_SIZE

      output.byteslice(0, MAX_OUTPUT_SIZE) + "\n... (truncated, exceeded 10MB limit)"
    end
  end
end
