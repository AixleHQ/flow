# frozen_string_literal: true

class SubStepRunSerializer < ApplicationSerializer
  attributes :id, :sub_step_id, :state, :note, :data, :started_at, :completed_at

  attribute :sub_step_name

  def sub_step_name
    object.sub_step.name
  end
end
