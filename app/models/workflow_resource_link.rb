# frozen_string_literal: true

# A workflow's base resource list, the `base_*_ids` of its config.
class WorkflowResourceLink < ApplicationRecord
  include ResourceLink

  belongs_to :workflow

  def self.owner_column = :workflow_id
end
