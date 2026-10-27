# frozen_string_literal: true

# Company runners, a tab of company settings: visible to every project of the
# company, managed by a company admin (docs/design/agent-runtimes/DESIGN.md §3.2).
class Web::Company::RunnersController < Web::Company::ApplicationController
  include RunnerManagement

  private

  def page_prefix = "Company/Settings"
  def runner_policy_class = Web::Company::RunnersPolicy

  def listed_runners
    current_company.runners.not_deleted.where(project_id: nil)
  end

  def build_runner
    current_company.runners.new(project: nil, created_by: current_user)
  end

  def runners_page_path = company_settings_runners_path
  def runner_page_path(runner) = company_settings_runner_path(runner)
end
