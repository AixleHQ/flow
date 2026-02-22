# frozen_string_literal: true

class WorkflowContextAssembler
  def initialize(step_run)
    @step_run = step_run
    @workflow_run = step_run.workflow_run
    @workflow = @workflow_run.workflow
    @step = step_run.step
  end

  def assemble
    sections = []
    sections << workflow_section
    sections << current_step_section
    sections << sub_steps_section if @step.sub_steps.any?
    sections << previous_steps_section if completed_steps.any?
    sections.join("\n\n")
  end

  private

  def workflow_section
    <<~MD
      # Workflow: #{@workflow.name}

      #{@workflow.description}

      **Mode:** #{@workflow_run.mode}
      **Run ID:** #{@workflow_run.id}
    MD
  end

  def current_step_section
    <<~MD
      ## Current Step #{@step.position}: #{@step.name}

      #{@step.description}

      ### Instructions

      #{@step.instructions}
    MD
  end

  def sub_steps_section
    lines = @step.sub_steps.order(:position).map do |ss|
      required = ss.required? ? "(required)" : "(optional)"
      "- [ ] #{ss.position}. #{ss.name} #{required}: #{ss.description}"
    end

    <<~MD
      ### Sub-steps

      #{lines.join("\n")}

      Use the `mark_sub_step` tool to update progress on each sub-step.
    MD
  end

  def previous_steps_section
    lines = completed_steps.map do |sr|
      note = sr.step_note.present? ? "\n  Note: #{sr.step_note}" : ""
      "- Step #{sr.step.position}: #{sr.step.name} (#{sr.state})#{note}"
    end

    <<~MD
      ### Previous Steps

      #{lines.join("\n")}
    MD
  end

  def completed_steps
    @completed_steps ||= @workflow_run.step_runs
                                       .includes(:step)
                                       .where.not(id: @step_run.id)
                                       .where(state: %w[completed skipped])
                                       .joins(:step)
                                       .order("steps.position ASC")
  end
end
