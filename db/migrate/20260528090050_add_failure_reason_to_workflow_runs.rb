# frozen_string_literal: true

class AddFailureReasonToWorkflowRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :workflow_runs, :failure_reason, :string
    add_column :workflow_runs, :failed_agent_credential_id, :bigint
    add_foreign_key :workflow_runs, :agent_credentials,
                    column: :failed_agent_credential_id,
                    on_delete: :nullify
    add_index :workflow_runs, :failed_agent_credential_id
  end
end
