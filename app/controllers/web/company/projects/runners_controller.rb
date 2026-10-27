# frozen_string_literal: true

# A project's runners page: the project's own runners and the company's
# (Runner.visible_for_project). Only the project's own are managed here; the
# policy refuses writes on a company runner (docs/design/agent-runtimes/DESIGN.md §3.2).
class Web::Company::Projects::RunnersController < Web::Company::Projects::ApplicationController
  include RunnerManagement

  private

  def page_prefix = "Projects/Runners"
  def runner_policy_class = Web::Company::Projects::RunnersPolicy

  def listed_runners
    Runner.visible_for_project(current_project)
  end

  def build_runner
    current_project.runners.new(company: current_project.company, created_by: current_user)
  end

  def runners_page_path = company_project_runners_path(current_project)
  def runner_page_path(runner) = company_project_runner_path(current_project, runner)
end
