# frozen_string_literal: true

class WorkflowRunStatsService
  Result = Struct.new(
    :completed, :in_progress, :failed, :queued, :total,
    keyword_init: true
  )

  def initialize(company, project: nil)
    @company = company
    @project = project
  end

  def call
    base = if project
      WorkflowRun.where(project_id: project.id)
    else
      WorkflowRun.joins(:project).where(projects: { company_id: company.id })
    end

    completed   = base.where(state: "completed").count
    in_progress = base.where(state: %w[running paused]).count
    failed      = base.where(state: %w[failed cancelled]).count
    queued      = base.where(state: "pending").count
    total       = completed + in_progress + failed + queued

    Result.new(
      completed: completed,
      in_progress: in_progress,
      failed: failed,
      queued: queued,
      total: total
    )
  end

  private

  attr_reader :company, :project
end
