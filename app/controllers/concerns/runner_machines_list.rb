# frozen_string_literal: true

# The Machines section of a `manual` runner's page, for the two runners
# controllers (docs/design/agent-runtimes/DESIGN.md §2.5, §11): read-only, the
# same on the company's and the project's page. The controller has already
# found the runner in its own scope.
module RunnerMachinesList
  extend ActiveSupport::Concern

  private

  def machines_prop(runner)
    return [] unless runner.manual?

    runner.environments.order(:id).map { |machine| RunnerMachineResource.new(machine).to_h }
  end
end
