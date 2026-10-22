# frozen_string_literal: true

class LlmCall < ApplicationRecord
  belongs_to :terminal_session
  belongs_to :workflow_run, optional: true
  belongs_to :step_run, optional: true

  scope :for_workflow_run, ->(id) { where(workflow_run_id: id) }
  scope :for_session, ->(id) { where(terminal_session_id: id) }
end
