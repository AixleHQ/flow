# frozen_string_literal: true

module ContainerStrategies
  # CustomToolStrategy — for custom (user-created) tools.
  # Inherits lifecycle from ToolStrategy, provides tool-specific data resolution.
  #
  # All tool_files are injected via Docker archive API (store_file) after container
  # creation, before start. Works with both text and binary files uniformly.
  #
  # Security: sandboxed (no bind mounts, no docker socket, resource-limited).
  # Output: stdout/stderr only — no file collection from container.
  class CustomToolStrategy < ToolStrategy
    def before_create_container(**)
      tool = input[:tool]
      raise ArgumentError, "Tool requires docker_image" if tool.docker_image.blank?
      super
    end

    def resolve_image = input[:tool].docker_image
    def build_working_dir = "/workspace"

    def build_cmd
      parameters = input[:parameters] || {}
      command = interpolate_command(input[:tool].command.presence || "/bin/sh", parameters)
      [ "/bin/sh", "-c", command ]
    end

    def start_container(container_id:, **)
      super
      store_tool_files(container_id)
      {}
    end

    def build_env_vars
      env = {}
      (input[:parameters] || {}).each { |k, v| env[k.to_s.upcase.gsub(/[^A-Z0-9_]/, "_")] = v.to_s }
      env.merge!(resolve_config_items)
      inject_project_env(env)
      super + env.map { |k, v| "#{k}=#{v}" }
    end

    def build_labels
      tool = input[:tool]
      { "aixle.type" => "tool_execution",
        "aixle.tool_id" => tool.id.to_s,
        "aixle.tool_name" => tool.name }
    end

    def build_host_config = build_host_config_with_limits

    private

    def interpolate_command(template, params)
      result = template.dup
      params.each { |key, value| result = result.gsub("{{#{key}}}", value.to_s) }
      result
    end

    def store_tool_files(container_id)
      input[:tool].tool_files.each do |tf|
        content = tf.binary? ? tf.file.download.read : (tf.content || "")
        mode = executable_path?(tf.path) ? 0o755 : 0o644
        runtime.store_file(container_id, tf.path, content, mode: mode)
      end
    end

    def executable_path?(path)
      ext = File.extname(path).downcase
      ext.empty? || %w[.sh .bash .py .rb .pl].include?(ext)
    end

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

    def inject_project_env(env)
      if (project = input[:project])
        env["AIXLE_PROJECT_ID"] = project.id.to_s
        env["AIXLE_PROJECT_NAME"] = project.name
      end
    end
  end
end
