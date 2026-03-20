# frozen_string_literal: true

class CompanyOverviewService
  Result = Struct.new(
    :sessions_launched, :total_spend_cents, :workflows_count,
    :board_tasks_count, :users_count, :agents_count, :projects_count,
    keyword_init: true
  )

  def initialize(company)
    @company = company
  end

  def call
    Result.new(
      sessions_launched: company.terminal_sessions.count,
      total_spend_cents: UsageStatistic
        .joins(terminal_session: :user)
        .where(users: { company_id: company.id })
        .sum(:cost_cents),
      workflows_count: Workflow.belonging_to_company(company).count,
      board_tasks_count: BoardTask.for_company(company).count,
      users_count: company.users.count,
      agents_count: Agent.belonging_to_company(company).count,
      projects_count: company.projects.count
    )
  end

  private

  attr_reader :company
end
