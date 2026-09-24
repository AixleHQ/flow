# frozen_string_literal: true

module ContainerStrategies
  # CustomToolStrategy — for custom (user-created) tools.
  # Inherits lifecycle from ToolStrategy, provides tool-specific data resolution.
  #
  # Tool files are written into the container once it is up, and the command
  # waits for them behind a start gate: a Kubernetes pod runs its command the
  # moment it is created, so "write before start" is not something every runtime
  # can offer. Works with both text and binary files uniformly.
  #
  # Security: sandboxed (no bind mounts, no docker socket, resource-limited).
  # Output: stdout/stderr only — no file collection from container.
  class CustomToolStrategy < ToolStrategy
    # Set by Tools::CallExecutor in place of a GitHub token: the token is minted
    # here, inside the activity, so it never rides in the workflow input.
    REPOSITORY_REFERENCE = "__aixle_repository_id"
    START_GATE = "/tmp/.aixle-tool-start"

    def before_create_container(**)
      tool = input[:tool]
      raise ArgumentError, "Tool requires docker_image" if tool.docker_image.blank?
      pin_image_digest!(tool)
      super
    end

    # Digest-pinned once resolved: a mutable tag (":latest") can't silently
    # swap the code a published tool runs. The pin resets when the user
    # legitimately changes docker_image (Tool#reset_image_digest).
    def resolve_image
      tool = input[:tool]
      tool.docker_image_digest.presence || tool.docker_image
    end
    def build_working_dir = "/workspace"

    def build_cmd
      command = interpolate_command(input[:tool].command.presence || "/bin/sh", parameters)
      return [ "/bin/sh", "-c", command ] unless stages_files?

      [ "/bin/sh", "-c",
        "until [ -e #{START_GATE} ]; do sleep 0.2 2>/dev/null || sleep 1; done; exec /bin/sh -c #{Shellwords.escape(command)}" ]
    end

    def start_container(container_id:, **)
      super
      return {} unless stages_files?

      runtime.wait_for_ready(resolve_container(container_id))
      store_tool_files(container_id)
      runtime.write_file(container_id, START_GATE, "")
      {}
    end

    def build_env_vars
      env = {}
      parameters.each { |k, v| env[k.to_s.upcase.gsub(/[^A-Z0-9_]/, "_")] = v.to_s }
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

    def parameters
      @parameters ||= with_repository_credential((input[:parameters] || {}).to_h.stringify_keys)
    end

    # The repository is re-resolved through the session the call came from, so
    # it still has to be attached when the container is actually created, and
    # the token is narrowed to that one repository.
    def with_repository_credential(params)
      repository_id = params.delete(REPOSITORY_REFERENCE)
      return params if repository_id.blank?

      session = ToolResult.find_by(id: input[:tool_result_id])&.terminal_session
      repository = session&.repositories&.find_by(id: repository_id)
      raise ArgumentError, "Repository #{repository_id} is not attached to this session" unless repository&.integration&.github?

      token = Github::TokenService.new(repository.integration)
                                  .generate_installation_token(repositories: [ repository.repo_name ])
      params.merge("GITHUB_TOKEN" => token)
    end

    # Best-effort: resolve the pulled image's repo digest and store it on the
    # tool row (update_columns on purpose — a digest stamp is not a definition
    # change). Runs where Docker is actually reachable (the Temporal worker),
    # never blocks execution on failure.
    def pin_image_digest!(tool)
      return if tool.docker_image_digest.present?

      digest = runtime.image_digest(tool.docker_image)
      tool.update_columns(docker_image_digest: digest) if digest.present?
    rescue StandardError => e
      Rails.logger.warn("[CustomToolStrategy] image digest pin skipped for tool ##{tool.id}: #{e.message}")
    end

    def interpolate_command(template, params)
      result = template.dup
      params.each { |key, value| result = result.gsub("{{#{key}}}", value.to_s) }
      result
    end

    def stages_files?
      input[:tool].tool_files.any?
    end

    # A file that did not land fails the run here, not as a confusing error from
    # the tool's own command later.
    def store_tool_files(container_id)
      input[:tool].tool_files.each do |tf|
        content = tf.binary? ? tf.file.download.read : (tf.content || "")
        mode = executable_path?(tf.path) ? 0o755 : 0o644
        next if runtime.write_file(container_id, tf.path, content, mode: mode)

        raise "could not write #{tf.path} into the tool container"
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
