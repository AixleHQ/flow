# frozen_string_literal: true

module ContextBuilders
  class WorkflowContext < Base
    def applicable?
      step_run.present?
    end

    def build
      sections = []
      sections << workflow_overview_section
      sections << trigger_message_section if trigger_message.present?
      sections << current_step_section
      sections << sub_steps_section if sub_steps.any?
      sections << previous_steps_section if completed_step_runs.any?
      sections << workflow_tools_section if sub_steps.any?
      sections
    end

    private

    def workflow_overview_section
      section(
        tag: "workflow-context",
        priority: :important,
        content: build_workflow_overview,
        position_hint: :top
      )
    end

    def current_step_section
      section(
        tag: "current-step",
        priority: :critical,
        content: build_current_step
      )
    end

    # When the run was started by a Slack (or other chat) trigger, surface the
    # originating message so the agent acts on what the user actually asked for —
    # otherwise it only sees the static step instructions.
    def trigger_message_section
      section(
        tag: "trigger-message",
        priority: :critical,
        content: build_trigger_message,
        position_hint: :top
      )
    end

    def build_trigger_message
      <<~MD.strip
        ## Triggering message

        This run was started by a Slack message#{trigger_user_suffix}. Treat it as the user's request and respond to it:

        > #{trigger_message.to_s.gsub("\n", "\n> ")}
      MD
    end

    def trigger_user_suffix
      user = workflow_run.shared_context.to_h.dig("slack", "user")
      user.present? ? " from <@#{user}>" : ""
    end

    def trigger_message
      @trigger_message ||= workflow_run.shared_context.to_h.dig("slack", "text")
    end

    def sub_steps_section
      section(
        tag: "sub-steps",
        priority: :important,
        content: build_sub_steps
      )
    end

    def previous_steps_section
      section(
        tag: "previous-steps",
        priority: :info,
        content: build_previous_steps
      )
    end

    def workflow_tools_section
      section(
        tag: "workflow-tools",
        priority: :important,
        content: build_workflow_tools
      )
    end

    def build_workflow_overview
      <<~MD.strip
        ## Workflow: #{workflow.name}

        #{workflow.description}

        **Mode:** #{workflow_run.mode} | **Run:** #{workflow_run.id}
        **Step #{step.position} of #{workflow.steps.not_deleted.count}**
      MD
    end

    def build_current_step
      lines = []
      lines << "## Step: #{step.name}"
      lines << ""
      lines << "### Instructions"
      lines << ""
      lines << step.instructions if step.instructions.present?
      lines.join("\n")
    end

    def build_sub_steps
      lines = [ "## Sub-Steps Checklist", "" ]

      sub_step_run_map = step_run.sub_step_runs.includes(:sub_step).index_by(&:sub_step_id)

      sub_steps.each do |ss|
        ssr = sub_step_run_map[ss.id]
        status = ssr ? ssr.state : "pending"
        icon = status_icon(status)
        id_ref = ssr ? " `id: #{ssr.id}`" : ""

        lines << "#{ss.position}. #{icon} **#{ss.name}**#{id_ref} [#{status}]"

        if ss.instructions.present?
          lines << ""
          ss.instructions.each_line { |l| lines << "   #{l.chomp}" }
          lines << ""
        end

        if ssr&.note.present?
          lines << "   → #{ssr.note.truncate(200)}"
        end
        if ssr&.data.present?
          lines << "   → data: #{ssr.data.to_json.truncate(300)}"
        end
      end

      lines << ""
      lines << "Track progress: call `mark_sub_step` with the sub-step `id` shown above."
      lines << "Mark `in_progress` when starting, `completed` when done."
      lines.join("\n")
    end

    def build_previous_steps
      lines = [ "## Previous Steps", "" ]

      completed_step_runs.each do |sr|
        prev_step = sr.step
        icon = sr.state == "skipped" ? "⏭️" : "✅"
        lines << "### #{prev_step.position}. #{icon} #{prev_step.name} [#{sr.state}]"

        if sr.step_note.present?
          lines << ""
          lines << sr.step_note.truncate(500)
        end

        completed_sub_runs = sr.sub_step_runs.select { |ssr| ssr.state.in?(%w[completed skipped]) }
        if completed_sub_runs.any?
          lines << ""
          completed_sub_runs.each do |ssr|
            sub_icon = ssr.state == "skipped" ? "⏭️" : "✅"
            line = "- #{sub_icon} #{ssr.sub_step.name}"
            line += " — #{ssr.note.truncate(150)}" if ssr.note.present?
            lines << line
            if ssr.data.present?
              lines << "  → data: #{ssr.data.to_json.truncate(200)}"
            end
          end
        end

        lines << ""
      end

      lines.join("\n")
    end

    def build_workflow_tools
      lines = []
      lines << "## Workflow Tools (MCP)"
      lines << ""
      lines << "You have special tools to track progress within this step:"
      lines << ""
      lines << "- **list_sub_steps** — List all sub-steps with their current statuses. Call this first to see what needs to be done."
      lines << "- **mark_sub_step** — Update a sub-step status. Parameters: `id` (sub-step run ID), `status` (`in_progress`/`completed`/`skipped`), optional `note` and `data`."
      lines << ""
      lines << "Always mark sub-steps as you work through them so the workflow dashboard stays up to date."

      lines.join("\n")
    end

    def sub_steps
      @sub_steps ||= step&.sub_steps&.active || SubStep.none
    end

    def completed_step_runs
      @completed_step_runs ||= workflow_run.step_runs
        .where.not(id: step_run.id)
        .where(state: %w[completed skipped])
        .joins(:step)
        .order("steps.position ASC")
        .includes(step: :sub_steps, sub_step_runs: :sub_step)
    end

    def non_interactive?
      session.mode == "non_interactive"
    end

    def status_icon(status)
      { "completed" => "✅", "in_progress" => "🔄", "skipped" => "⏭️" }.fetch(status, "⬜")
    end
  end
end
