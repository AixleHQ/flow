# frozen_string_literal: true

# A runner as a picker or a "Runs on" badge shows it (DESIGN.md §11): enough to
# name it, say whether it can be used, and say who operates it.
class RunnerSummaryResource < ApplicationResource
  typelize_from Runner

  attributes :id, :name, :project_id, :runner_type, :status

  typelize :boolean
  attribute :deleted do |runner|
    runner.deleted?
  end

  typelize :string
  attribute :operated_by do |runner|
    runner.operated_by
  end
end
