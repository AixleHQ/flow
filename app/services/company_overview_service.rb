# frozen_string_literal: true

class CompanyOverviewService
  Result = Struct.new(
    :sessions_launched, :sessions_running, :total_spend_cents, :workflows_count,
    :board_tasks_count,
    keyword_init: true
  )

  def initialize(company, project: nil)
    @company = company
    @project = project
  end

  def call
    Result.new(
      sessions_launched: sessions_scope.count,
      sessions_running: sessions_scope.where(state: %w[running ready]).count,
      total_spend_cents: sessions_scope.sum(:cost_cents),
      workflows_count: workflows_scope.count,
      board_tasks_count: board_tasks_scope.count
    )
  end

  private

  attr_reader :company, :project

  def sessions_scope
    if project
      TerminalSession.where(project_id: project.id)
    else
      company.terminal_sessions
    end
  end

  def workflows_scope
    if project
      Workflow.for_project(project)
    else
      # All workflows across the company's projects (company-level workflows were removed).
      company.workflows.active
    end
  end

  def board_tasks_scope
    if project
      board = project.board
      return BoardTask.none unless board

      BoardTask.where(board_id: board.id)
    else
      BoardTask.for_company(company)
    end
  end
end
