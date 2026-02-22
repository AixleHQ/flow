# frozen_string_literal: true

class SubStepRun < ApplicationRecord
  extend Enumerize

  belongs_to :step_run
  belongs_to :sub_step

  enumerize :state, in: %i[pending in_progress completed skipped], default: :pending,
                    predicates: true, scope: true
end
