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

    completed   = base.completed.count
    in_progress = base.underway.count
    failed      = base.aborted.count
    queued      = base.pending.count
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
