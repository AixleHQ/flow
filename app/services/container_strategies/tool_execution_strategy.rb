# frozen_string_literal: true

require "base64"
require "shellwords"
require "timeout"

module ContainerStrategies
  # ToolExecutionStrategy
  # Strategy for executing custom tools in Docker containers.
  #
  # Tool command runs as the container's main process (not via exec).
  # Container exits naturally when command finishes.
  #
  class ToolExecutionStrategy < BaseStrategy
    DEFAULT_TIMEOUT = 300
    MAX_TIMEOUT = 1800
    MAX_OUTPUT_SIZE = 10.megabytes
    TIMEOUT_EXIT_CODE = 124

    def phase_config(phase)
      case phase
      when :exec    then { timeout: [ input[:timeout] || DEFAULT_TIMEOUT, MAX_TIMEOUT ].min }
      when :cleanup then { timeout: 60, always: true }
      else               { timeout: 120 }
      end
    end

    # == before_create_container(**) → { image:, env_vars:, ... } ==

    def before_create_container(**)
      tool = input[:tool]
      raise ArgumentError, "Tool must be custom" unless tool.custom?
      raise ArgumentError, "Tool requires docker_image" if tool.docker_image.blank?

      {
        image: resolve_image,
        env_vars: build_env_vars,
        labels: build_labels,
        host_config: build_host_config,
        cmd: build_cmd,
        working_dir: build_working_dir,
        exposed_ports: build_exposed_ports
      }
    end

    def resolve_image
      input[:tool].docker_image
    end

    def build_env_vars
      env_hash = {}

      (input[:parameters] || {}).each do |key, value|
        env_hash[key.to_s.upcase.gsub(/[^A-Z0-9_]/, "_")] = value.to_s
      end

      env_hash.merge!(resolve_config_items)

      if (project = input[:project])
        env_hash["PALAD_PROJECT_ID"] = project.id.to_s
        env_hash["PALAD_PROJECT_NAME"] = project.name
      end

      env_hash.map { |k, v| "#{k}=#{v}" }
    end

    def build_labels
      tool = input[:tool]
      { "palad.type" => "tool_execution", "palad.tool_id" => tool.id.to_s, "palad.tool_name" => tool.name }
    end

    def build_host_config = build_host_config_with_limits

    def build_cmd
      tool = input[:tool]
      parameters = input[:parameters] || {}
      command = build_command(tool, parameters)

      if tool.tool_files.any?
        setup = tool.tool_files.map { |tf| file_setup_command(tf) }
        [ "/bin/sh", "-c", (setup + [ command ]).join(" && ") ]
      else
        [ "/bin/sh", "-c", command ]
      end
    end

    def build_working_dir = "/workspace"

    # == start_container(container_id:, **) → {} ==
    # Tool containers run command directly, skip health check.

    def start_container(container_id:, **)
      container = resolve_container(container_id)
      runtime.start_container(container)
      {}
    end

    # == exec(container_id:, **) → { exit_code:, stdout:, stderr:, duration_ms:, timed_out: } ==

    def exec(container_id:, **)
      container = resolve_container(container_id)
      exec_timeout = [ input[:timeout] || DEFAULT_TIMEOUT, MAX_TIMEOUT ].min
      start_time = Time.current

      begin
        Timeout.timeout(exec_timeout) do
          wait_result = runtime.wait_container(container)
          exit_code = wait_result["StatusCode"] || wait_result[:StatusCode] || -1
          logs = runtime.container_logs(container)
          duration_ms = ((Time.current - start_time) * 1000).to_i

          Rails.logger.info("[ToolExecution] Completed: exit_code=#{exit_code}, duration=#{duration_ms}ms")

          {
            exit_code: exit_code,
            stdout: truncate_output(logs[:stdout]),
            stderr: truncate_output(logs[:stderr]),
            duration_ms: duration_ms,
            timed_out: false
          }
        end
      rescue Timeout::Error
        handle_execution_timeout(container, start_time, exec_timeout)
      end
    end

    # == before_cleanup(container_id:, **) → { output_files_count:, output_files_paths: } ==

    def before_cleanup(container_id: nil, **)
      tool = input[:tool]
      return {} unless tool.respond_to?(:output_paths) && tool.output_paths.present?
      return {} if container_id.blank?

      container = resolve_container(container_id)
      output_files = {}

      tool.output_paths.each do |path|
        content = runtime.read_file(container, path)
        output_files[path] = content if content.present?
      rescue StandardError => e
        Rails.logger.warn("[ToolExecution] Failed to extract #{path}: #{e.message}")
      end

      Rails.logger.info("[ToolExecution] Collected #{output_files.size} output files")
      { output_files_count: output_files.size, output_files_paths: output_files.keys }
    end

    private

    def resolve_config_items
      tool = input[:tool]
      project = input[:project]
      return {} if tool.required_config_items.blank?

      company = project&.company || tool.scope
      tool.required_config_items.each_with_object({}) do |name, env_vars|
        config_item = find_config_item(name, project, company)
        next unless config_item
        env_vars[name.upcase.gsub(/[^A-Z0-9_]/, "_")] = config_item.decrypted_value
      end
    end

    def find_config_item(name, project, company)
      if project
        ConfigItem.find_by(name: name, scope: project) || ConfigItem.find_by(name: name, scope: company)
      else
        ConfigItem.find_by(name: name, scope: company)
      end
    end

    def file_setup_command(tool_file)
      dir = Shellwords.escape(File.dirname(tool_file.path))
      path = Shellwords.escape(tool_file.path)
      encoded = Base64.strict_encode64(tool_file.content || "")
      "mkdir -p #{dir} && echo '#{encoded}' | base64 -d > #{path}"
    end

    def build_command(tool, parameters)
      command = tool.command.presence || "/bin/sh"
      parameters.each { |key, value| command = command.gsub("{{#{key}}}", value.to_s) }
      command
    end

    def handle_execution_timeout(container, start_time, timeout)
      duration_ms = ((Time.current - start_time) * 1000).to_i
      container.kill rescue nil

      logs = begin
        runtime.container_logs(container)
      rescue StandardError
        { stdout: "", stderr: "" }
      end

      Rails.logger.warn("[ToolExecution] TIMEOUT after #{timeout}s")

      {
        exit_code: TIMEOUT_EXIT_CODE,
        stdout: truncate_output(logs[:stdout]),
        stderr: "Tool execution timed out after #{timeout} seconds\n#{truncate_output(logs[:stderr])}",
        duration_ms: duration_ms,
        timed_out: true
      }
    end

    def truncate_output(output)
      return "" if output.nil?
      return output if output.bytesize <= MAX_OUTPUT_SIZE
      output.byteslice(0, MAX_OUTPUT_SIZE) + "\n... (truncated, exceeded 10MB limit)"
    end
  end
end
