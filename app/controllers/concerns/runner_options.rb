# frozen_string_literal: true

# The runners a project's "Runner" and "Runs on" selects offer (DESIGN.md §11):
# the ones the project can see, each with its status, or none without the flag.
# `including:` adds the runner a workflow already names when it is no longer
# listed, a deleted one, so the builder can name it in its warning (§3.4).
module RunnerOptions
  extend ActiveSupport::Concern

  private

  def runner_options(project = current_project, including: nil)
    return [] unless Feature.enabled?(:external_runners, company: project.company)

    runners = Runner.visible_for_project(project).includes(:company, :project).order(:name).to_a
    runners << including if including && runners.exclude?(including)
    runners.map { |runner| RunnerSummaryResource.new(runner).to_h }
  end
end
