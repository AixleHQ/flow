# frozen_string_literal: true

class StepResourceLink < ApplicationRecord
  include ResourceLink

  belongs_to :step

  def self.owner_column = :step_id
end
