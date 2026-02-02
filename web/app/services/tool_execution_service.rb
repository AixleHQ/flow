# frozen_string_literal: true

require "docker"
require "base64"

# Tool Execution Service
# Runs custom tools in Docker containers with file injection and config injection
#
# Returns: { exit_code: int, stdout: string, stderr: string, duration_ms: int }

class ToolExecutionService
  class ExecutionError < StandardError; end
  class TimeoutError < ExecutionError; end

  DEFAULT_TIMEOUT = 5.minutes
  MAX_TIMEOUT = 30.minutes
  MAX_OUTPUT_SIZE = 1.megabyte
  DOCKER_NETWORK = ENV.fetch("DOCKER_NETWORK", "app_default")

  class << self
    # Execute a tool in Docker container
    #
    # @param tool [Tool] Tool to execute
    # @param parameters [Hash] Input parameters for the tool
    # @param project [Project, nil] Project context (for config item resolution)
    # @param timeout [Integer] Execution timeout in seconds
    # @return [Hash] { exit_code:, stdout:, stderr:, duration_ms: }
    def execute(tool:, parameters: {}, project: nil, timeout: DEFAULT_TIMEOUT)
      raise ArgumentError, "Tool must be custom" unless tool.custom?
      raise ArgumentError, "Tool requires docker_image" if tool.docker_image.blank?

      timeout = [ timeout.to_i, MAX_TIMEOUT.to_i ].min
      timeout = DEFAULT_TIMEOUT.to_i if timeout <= 0

      start_time = Time.current
      container = nil

      begin
        # Resolve config items
        env_vars = resolve_config_items(tool, project)

        # Build command
        command = build_command(tool, parameters)

        Rails.logger.info("[ToolExecution] Starting: #{tool.name}, image: #{tool.docker_image}")
        Rails.logger.info("[ToolExecution] Command: #{command}")
        Rails.logger.info("[ToolExecution] Env vars: #{env_vars.keys.join(', ')}")
        Rails.logger.info("[ToolExecution] Timeout: #{timeout}s")

        # Create container (starts with sleep to allow file injection)
        container = create_container(
          image: tool.docker_image,
          env_vars: env_vars
        )

        # Start container (runs sleep infinity)
        container.start

        # Inject tool files into running container
        inject_tool_files(container, tool)

        # Execute the actual command and wait for completion
        result = execute_command(container, command, timeout)

        duration_ms = ((Time.current - start_time) * 1000).to_i

        Rails.logger.info("[ToolExecution] Completed: exit_code=#{result[:exit_code]}, duration=#{duration_ms}ms")

        {
          exit_code: result[:exit_code],
          stdout: truncate_output(result[:stdout]),
          stderr: truncate_output(result[:stderr]),
          duration_ms: duration_ms
        }
      rescue Timeout::Error
        duration_ms = ((Time.current - start_time) * 1000).to_i
        Rails.logger.error("[ToolExecution] Timeout after #{duration_ms}ms")

        {
          exit_code: 124, # Standard timeout exit code
          stdout: "",
          stderr: "Execution timed out after #{timeout} seconds",
          duration_ms: duration_ms
        }
      ensure
        cleanup_container(container) if container
      end
    end

    private

    # Resolve config items for tool
    # Returns hash of env_var_name => value
    def resolve_config_items(tool, project)
      return {} if tool.required_config_items.blank?

      env_vars = {}
      company = project&.company || tool.scope

      tool.required_config_items.each do |name|
        # Try project level first, then company level
        config_item = if project
                        ConfigItem.find_by(name: name, scope: project) ||
                          ConfigItem.find_by(name: name, scope: company)
        else
                        ConfigItem.find_by(name: name, scope: company)
        end

        next unless config_item

        # Convert name to env var format (uppercase, sanitize)
        env_name = name.upcase.gsub(/[^A-Z0-9_]/, "_")
        env_vars[env_name] = config_item.decrypted_value
      end

      env_vars
    end

    # Build command from tool definition and parameters
    def build_command(tool, parameters)
      command = tool.command.presence || "/bin/sh"

      # Replace {{param}} placeholders with values
      parameters.each do |key, value|
        command = command.gsub("{{#{key}}}", value.to_s)
      end

      command
    end

    # Create Docker container (starts with sleep to allow file injection)
    def create_container(image:, env_vars:)
      container_config = {
        "Image" => image,
        "Cmd" => [ "sleep", "infinity" ],
        "Env" => env_vars.map { |k, v| "#{k}=#{v}" },
        "WorkingDir" => "/workspace",
        "HostConfig" => {
          "NetworkMode" => DOCKER_NETWORK,
          "AutoRemove" => false,
          # Memory limit to prevent abuse
          "Memory" => 512 * 1024 * 1024, # 512MB
          "MemorySwap" => 512 * 1024 * 1024,
          # CPU limit
          "CpuPeriod" => 100_000,
          "CpuQuota" => 50_000 # 50% of one CPU
        },
        "Labels" => {
          "palad.type" => "tool_execution",
          "palad.tool_id" => image.to_s
        }
      }

      Docker::Container.create(container_config)
    end

    # Inject tool files into container via exec
    def inject_tool_files(container, tool)
      return if tool.tool_files.empty?

      tool.tool_files.each do |tool_file|
        # Create parent directory
        dir = File.dirname(tool_file.path)
        container.exec([ "mkdir", "-p", dir ])

        # Write file content using base64 to handle binary/special chars
        encoded = Base64.strict_encode64(tool_file.content || "")
        container.exec([ "/bin/sh", "-c", "echo '#{encoded}' | base64 -d > #{tool_file.path}" ])
      end

      Rails.logger.info("[ToolExecution] Injected #{tool.tool_files.count} files into container")
    end

    # Execute command in running container via exec
    def execute_command(container, command, timeout)
      stdout_buffer = StringIO.new
      stderr_buffer = StringIO.new

      Timeout.timeout(timeout) do
        # Create exec instance
        exec_result = container.exec(
          [ "/bin/sh", "-c", command ],
          wait: timeout,
          stdout: true,
          stderr: true
        )

        # exec returns [stdout_array, stderr_array, exit_code]
        stdout_lines, stderr_lines, exit_code = exec_result

        {
          exit_code: exit_code,
          stdout: stdout_lines.join,
          stderr: stderr_lines.join
        }
      end
    end

    # Truncate output to prevent memory issues
    def truncate_output(output)
      return "" if output.nil?

      if output.bytesize > MAX_OUTPUT_SIZE
        output.byteslice(0, MAX_OUTPUT_SIZE) + "\n... (truncated)"
      else
        output
      end
    end

    # Cleanup container
    def cleanup_container(container)
      container.stop("t" => 2) rescue nil
      container.remove(force: true) rescue nil
    rescue StandardError => e
      Rails.logger.warn("[ToolExecution] Cleanup failed: #{e.message}")
    end
  end
end
