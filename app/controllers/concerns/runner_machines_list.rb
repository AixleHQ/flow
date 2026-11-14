# frozen_string_literal: true

# The Machines section of a `manual` runner's page, for the two runners
# controllers (docs/design/agent-runtimes/DESIGN.md §2.5, §11): read-only, the
# same on the company's and the project's page. The controller has already
# found the runner in its own scope.
module RunnerMachinesList
  extend ActiveSupport::Concern

  private

  # The runners of the list, each with its machines busy/total (§11).
  def runners_prop(runners)
    counts = Runners::Machines.counts(runners)
    runners.map { |runner| RunnerResource.new(runner, params: { machine_counts: counts }).to_h }
  end

  def machines_prop(runner)
    return [] unless runner.manual?

    RunnerMachineResource.new(runner.environments.includes(:created_by).order(:id)).to_h
  end
end
