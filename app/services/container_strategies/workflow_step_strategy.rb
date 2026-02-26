# frozen_string_literal: true

module ContainerStrategies
  # WorkflowStepStrategy
  # Strategy for workflow step containers — reuses AgentSessionStrategy behavior
  # but labels the session as "workflow_step" and always operates in non-interactive
  # mode (the agent receives its prompt from the step instructions).
  #
  class WorkflowStepStrategy < AgentSessionStrategy
    def phase_config(phase)
      case phase
      when :pull_image then { timeout: 600 }
      when :exec        then { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
      when :cleanup     then { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } }
      else                   { timeout: 300 }
      end
    end

    def build_env_vars
      env_vars_list = super

      session = TerminalSession.find(input[:session_id])
      step_run = session.step_run
      step = step_run&.step

      prompt = build_workflow_prompt(step, step_run)
      upsert_env_var(env_vars_list, "AGENT_PROMPT", prompt) if prompt.present?

      if step&.agent.present?
        upsert_env_var(env_vars_list, "CONFIGURED_AGENT_PERSONA", step.agent.persona)
        upsert_env_var(env_vars_list, "CONFIGURED_AGENT_PRINCIPLES", step.agent.principles)
      end

      env_vars_list
    end

    def before_cleanup(container_id: nil, **)
      return {} if container_id.blank?

      container = resolve_container(container_id)
      session = TerminalSession.find(input[:session_id])
      agent_service = AgentCredentialsService.for(input[:agent_type])

      logs_count, log_contents = collect_logs(container, session, agent_service)
      logs_count += collect_terminal_output(container, session)
      collect_usage(session, agent_service, log_contents)

      outputs_count = collect_workflow_outputs(container_id)

      Rails.logger.info("[WorkflowStepStrategy] Cleanup: #{logs_count} logs, #{outputs_count} workflow assets")
      { logs_count: logs_count, outputs_count: outputs_count }
    end

    def before_exec(container_id:, **)
      result = super
      inject_prior_step_outputs(container_id)
      result
    end

    def build_labels
      super.merge("palad.session_type" => "workflow_step")
    end

    protected

    def session_type = "workflow_step"

    def services_ports
      [ 7681 ]
    end

    private

    def collect_workflow_outputs(container_id)
      session = TerminalSession.find(input[:session_id])
      step_run = session.step_run
      unless step_run
        Rails.logger.info("[WorkflowStepStrategy] No step_run for session #{session.id}, skipping output collection")
        return 0
      end

      workflow_run = step_run.workflow_run
      container = resolve_container(container_id)
      output_dir = "/workspace/outputs"

      result = runtime.exec(
        container,
        ["/bin/sh", "-c", "find #{output_dir} -type f 2>/dev/null || true"],
        stdout: true, stderr: true
      )
      Rails.logger.info("[WorkflowStepStrategy] find exit=#{result[2]}, stdout=#{result[0].join.strip[0..200]}")
      return 0 unless result[2].zero?

      files = result[0].join.split("\n").reject(&:blank?)
      Rails.logger.info("[WorkflowStepStrategy] Found #{files.size} output files for step_run=#{step_run.id}")
      count = 0

      files.each do |file_path|
        relative = file_path.sub("#{output_dir}/", "")
        content = read_file_from_container(container, file_path)
        next if content.blank?

        tmpfile = Tempfile.new(["wf_output_", File.extname(relative)])
        tmpfile.binmode
        tmpfile.write(content)
        tmpfile.rewind

        content_type = Marcel::MimeType.for(tmpfile, name: relative)

        workflow_run.workflow_run_assets.create!(
          name: relative,
          produced_by_step_run: step_run,
          content_type: content_type,
          file_size: content.bytesize,
          s3_key: "workflow_runs/#{workflow_run.id}/steps/#{step_run.id}/#{relative}",
          file: tmpfile
        )
        count += 1
      rescue StandardError => e
        Rails.logger.warn("[WorkflowStepStrategy] Failed to collect output #{file_path}: #{e.message}")
      ensure
        tmpfile&.close!
      end

      count
    rescue StandardError => e
      Rails.logger.warn("[WorkflowStepStrategy] Output collection failed: #{e.message}")
      0
    end

    def inject_prior_step_outputs(container_id)
      session = TerminalSession.find(input[:session_id])
      step_run = session.step_run
      return unless step_run

      workflow_run = step_run.workflow_run
      step = step_run.step
      container = resolve_container(container_id)

      runtime.exec(container, ["mkdir", "-p", "/workspace/assets"])

      injected_names = []

      dep_ids = step.depends_on_step_ids
      if dep_ids.present?
        prior_assets = workflow_run.workflow_run_assets
          .joins("JOIN step_runs ON step_runs.id = workflow_run_assets.produced_by_step_run_id")
          .where(step_runs: { step_id: dep_ids })

        prior_assets.each do |wra|
          next unless wra.file
          download_to_container(container, wra.file.url, "/workspace/assets/#{wra.name}")
          injected_names << wra.name
        rescue StandardError => e
          Rails.logger.warn("[WorkflowStepStrategy] Failed to inject #{wra.name}: #{e.message}")
        end
      end

      inject_workflow_run_assets(container, workflow_run, injected_names)

      Rails.logger.info("[WorkflowStepStrategy] Injected #{injected_names.size} files into /workspace/assets/: #{injected_names.join(', ')}")
    end

    def inject_workflow_run_assets(container, workflow_run, injected_names)
      ids = workflow_run.input_asset_ids
      return if ids.blank?

      Asset.where(id: ids).each do |asset|
        version = asset.latest_version
        next unless version&.file

        download_to_container(container, version.file.url, "/workspace/assets/#{asset.name}")
        injected_names << asset.name
      rescue StandardError => e
        Rails.logger.warn("[WorkflowStepStrategy] Failed to inject run asset #{asset.name}: #{e.message}")
      end
    end


    def download_to_container(container, url, target_path)
      rewritten = rewrite_url_for_container(url)
      runtime.exec(container, ["sh", "-c", "curl -sSL -o '#{target_path}' '#{rewritten}'"])
      Rails.logger.info("[WorkflowStepStrategy] Downloaded → #{target_path}")
    end

    def rewrite_url_for_container(url)
      host = Settings.container_asset_host
      return url if host.blank?

      override = URI.parse(host.start_with?("http") ? host : "http://#{host}")
      uri = URI.parse(url)
      uri.scheme = override.scheme
      uri.host = override.host
      uri.port = override.port
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def build_workflow_prompt(step, step_run)
      parts = []
      parts << build_session_context_section(step_run)
      parts << step.instructions if step&.instructions.present?

      sub_steps = step&.sub_steps&.order(:position)
      if sub_steps.present? && sub_steps.any?
        parts << build_sub_steps_section(sub_steps, step_run)
        parts << build_workflow_tools_section
      end

      parts.compact_blank.join("\n\n")
    end

    def build_sub_steps_section(sub_steps, step_run)
      lines = [ "## Sub-steps for this step", "" ]
      sub_step_runs = step_run&.sub_step_runs&.includes(:sub_step)&.index_by(&:sub_step_id) || {}

      sub_steps.each do |ss|
        ssr = sub_step_runs[ss.id]
        status = ssr ? ssr.state : "pending"
        id_hint = ssr ? " (id: #{ssr.id})" : ""
        line = "#{ss.position}. **#{ss.name}**#{id_hint} [#{status}]"
        line += " — #{ss.description}" if ss.description.present?
        lines << line
      end

      lines << ""
      lines << "Track your progress: call `mark_sub_step` with the sub-step `id` shown above."
      lines << "Mark as `in_progress` when you start, `completed` when done."
      lines << ""
      lines << "**IMPORTANT:** Do NOT mark the last sub-step as `completed` until ALL work is fully done — including writing output files to `/workspace/outputs/`. Marking the last sub-step completed triggers session termination."
      lines.join("\n")
    end

    def build_workflow_tools_section
      <<~TOOLS
        ## Workflow tools available via MCP

        You have special tools to track progress within this step:

        - **list_sub_steps** — List all sub-steps with their current statuses. Call this first to see what needs to be done.
        - **mark_sub_step** — Update a sub-step status. Parameters: `id` (sub-step run ID), `status` (`in_progress`/`completed`/`skipped`), optional `note` and `data`.
        - **write_step_note** — Save a note visible to subsequent steps and workflow operators. Parameter: `note` (text).

        Always mark sub-steps as you work through them so the workflow dashboard stays up to date.
      TOOLS
    end

    def build_session_context_section(step_run)
      session = TerminalSession.find(input[:session_id])
      lines = []

      repos = session.repositories.to_a
      if repos.any?
        lines << "## Available Repositories"
        lines << ""
        repos.each do |repo|
          lines << "- **#{repo.full_name}** (repository_id: #{repo.id}) — mounted at /workspace/repo/"
        end
        lines << ""
      end

      workflow_run = step_run&.workflow_run
      if workflow_run&.input_asset_ids&.any?
        lines << "## Input Assets (pre-loaded in /workspace/assets/)"
        lines << ""
        Asset.where(id: workflow_run.input_asset_ids).each do |asset|
          lines << "- **#{asset.name}** (id: #{asset.id}) → `/workspace/assets/#{asset.name}`"
        end
        lines << ""
      end

      lines.any? ? lines.join("\n") : nil
    end
  end
end
