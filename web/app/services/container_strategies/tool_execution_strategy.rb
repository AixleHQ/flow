# frozen_string_literal: true

require "base64"
require "timeout"

module ContainerStrategies
  # ToolExecutionStrategy
  # Strategy for executing custom tools in Docker containers
  #
  # Lifecycle phases:
  #   - before_create: Resolve image, build env vars from config items
  #   - create: Create container with resource limits
  #   - start: Start container (runs sleep infinity)
  #   - before_exec: Inject tool files
  #   - exec: Execute tool command with timeout
  #   - before_cleanup: Collect output artifacts
  #   - cleanup: Stop and remove container
  #
  # Input:
  #   - tool: Tool model instance
  #   - parameters: Hash of command parameters
  #   - project: Project model instance (optional, for config resolution)
  #   - timeout: Execution timeout in seconds (optional, default 300)
  #
  # @example
  #   strategy = ToolExecutionStrategy.new(
  #     tool: tool,
  #     parameters: { query: "hello" },
  #     project: project,
  #     timeout: 600
  #   )
  #   result = ContainerService.execute(strategy: strategy, input: strategy.input)
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
      env_hash = resolve_config_items
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
      # Start with sleep to allow file injection before exec
      [ "sleep", "infinity" ]
    end

    def build_working_dir
      "/workspace"
    end

    def timeout_for(phase)
      return nil unless phase == :exec

      requested = input[:timeout] || DEFAULT_TIMEOUT
      [ requested.to_i, MAX_TIMEOUT ].min
    end

    # == Lifecycle: before_exec ==
    # Inject tool files into container

    def before_exec(context)
      tool = input[:tool]
      return if tool.tool_files.empty?

      container = context[:container]
      tool.tool_files.each do |tool_file|
        inject_file_into_container(container, tool_file)
      end

      Rails.logger.info("[ToolExecution] Injected #{tool.tool_files.count} files")
    end

    # == Lifecycle: exec ==
    # Execute tool command with timeout

    def exec(context)
      tool = input[:tool]
      parameters = input[:parameters] || {}
      timeout = timeout_for(:exec)

      command = build_command(tool, parameters)
      Rails.logger.info("[ToolExecution] Executing: #{command} (timeout: #{timeout}s)")

      start_time = Time.current

      begin
        result = execute_command_in_container(context[:container], command)
        duration_ms = ((Time.current - start_time) * 1000).to_i

        context[:result] = {
          exit_code: result[:exit_code],
          stdout: truncate_output(result[:stdout]),
          stderr: truncate_output(result[:stderr]),
          duration_ms: duration_ms,
          timed_out: false
        }

        Rails.logger.info("[ToolExecution] Completed: exit_code=#{result[:exit_code]}, duration=#{duration_ms}ms")
      rescue Timeout::Error
        handle_execution_timeout(context, start_time, timeout)
      end
    end

    # == Lifecycle: before_cleanup ==
    # Collect output artifacts from specified paths

    def before_cleanup(context)
      tool = input[:tool]
      return unless tool.respond_to?(:output_paths) && tool.output_paths.present?

      container = context[:container]
      output_files = {}

      tool.output_paths.each do |path|
        content = read_file_from_container(container, path)
        output_files[path] = content if content.present?
      rescue StandardError => e
        Rails.logger.warn("[ToolExecution] Failed to extract #{path}: #{e.message}")
      end

      context[:result] ||= {}
      context[:result][:output_files] = output_files
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

        # Convert name to env var format (uppercase, sanitize)
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

    # Inject file into container via exec
    #
    # @param container [Docker::Container] Container instance
    # @param tool_file [ToolFile] File to inject
    def inject_file_into_container(container, tool_file)
      # Create parent directory
      dir = File.dirname(tool_file.path)
      container.exec([ "mkdir", "-p", dir ])

      # Write file content using base64 to handle binary/special chars
      encoded = Base64.strict_encode64(tool_file.content || "")
      container.exec([ "/bin/sh", "-c", "echo '#{encoded}' | base64 -d > #{tool_file.path}" ])
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

    # Execute command in container
    #
    # @param container [Docker::Container] Container instance
    # @param command [String] Command to execute
    # @return [Hash] { exit_code:, stdout:, stderr: }
    def execute_command_in_container(container, command)
      # exec returns [stdout_array, stderr_array, exit_code]
      stdout_lines, stderr_lines, exit_code = container.exec(
        [ "/bin/sh", "-c", command ],
        stdout: true,
        stderr: true
      )

      {
        exit_code: exit_code,
        stdout: stdout_lines.join,
        stderr: stderr_lines.join
      }
    end

    # Handle execution timeout
    #
    # @param context [Hash] Execution context
    # @param start_time [Time] Execution start time
    # @param timeout [Integer] Timeout that was exceeded
    def handle_execution_timeout(context, start_time, timeout)
      duration_ms = ((Time.current - start_time) * 1000).to_i

      # Kill container immediately to stop any running process
      begin
        context[:container].kill
      rescue StandardError
        nil
      end

      context[:result] = {
        exit_code: TIMEOUT_EXIT_CODE,
        stdout: "",
        stderr: "Tool execution timed out after #{timeout} seconds",
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
