# frozen_string_literal: true

# Company-scoped trigger events. Slack events come from a workspace that belongs
# to a company (not a single project) and fan out to that company's projects, so
# they carry company_id with a null project_id. Other event sources stay
# project-scoped (project_id set).
class AddCompanyToTriggerEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :trigger_events, :company_id, :bigint
    add_index :trigger_events, [ :company_id, :event_type ]
  end
end
