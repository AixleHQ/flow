# frozen_string_literal: true

# A runner as the "Runs on" badge shows it on sessions, runs and the board's
# run history (DESIGN.md §11): its name and type, and whether its page is still
# there to link to. Who operates it is the pickers' concern (RunnerSummaryResource).
class RunnerBadgeResource < ApplicationResource
  typelize_from Runner

  attributes :id, :name, :runner_type

  typelize :boolean
  attribute :deleted do |runner|
    runner.deleted?
  end
end
