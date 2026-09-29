# frozen_string_literal: true

module Versions
  # Records, at launch, the versions a step and its session run with. Runtime
  # still reads the live rows (docs/design/entity-versioning.md §10), so this is
  # the record of what those rows were — a save mid-run shows up as the next
  # step naming a newer workflow version.
  module LaunchRecord
    module_function

    def record!(session, step_run: nil)
      ids = {
        "agent" => version_id(session.configured_agent),
        "skills" => session.skills.map { |skill| version_id(skill) },
        "tools" => session.tools.select(&:db_source?).map { |tool| version_id(tool) },
        "mcp_servers" => session.mcp_servers.reject(&:internal?).map { |server| version_id(server) }
      }
      if step_run
        workflow_version = version_id(step_run.step.workflow)
        ids["workflow"] = workflow_version
        step_run.update_column(:workflow_version_id, workflow_version)
      end
      session.update_column(:version_ids, ids.transform_values { |v| v.is_a?(Array) ? v.compact : v }.compact)
    end

    # An entity that has never been saved since history began gets its baseline
    # here, so every launch names a real version.
    def version_id(record)
      return nil unless record

      Versions.ensure_baseline!(record) if record.current_version_number.zero?
      record.entity_versions.reorder(number: :desc).pick(:id)
    end
  end
end
