# frozen_string_literal: true

module Versions
  # Resolves the resource ids inside a workflow's snapshots to display names:
  # { "Tool" => { "12" => { name: "Deploy", archived: true } }, ... }. Rows that
  # no longer exist are simply absent, which the diff shows as "#12 (deleted)".
  module ReferenceNames
    STEP_KEYS = { "agent_id" => "Agent" }.merge(Snapshots::Workflow::STEP_REFERENCES).freeze
    CONFIG_KEYS = Snapshots::Workflow::CONFIG_REFERENCES
    WORKFLOW_KEYS = { "runner_id" => "Runner" }.freeze

    module_function

    def for(version)
      return {} unless version.versionable_type == "Workflow"

      ids = Hash.new { |h, k| h[k] = Set.new }
      snapshots(version).each { |snapshot| collect(snapshot, ids) }
      ids.to_h { |model, set| [ model, names(model, set.to_a, workflow: version.versionable) ] }
    end

    def snapshots(version)
      scope = EntityVersion.where(versionable_type: "Workflow", versionable_id: version.versionable_id)
      [ version.snapshot, scope.where(number: ...version.number).order(number: :desc).pick(:snapshot),
        Snapshot.dump(version.versionable) ].compact
    end

    def collect(snapshot, ids)
      WORKFLOW_KEYS.each { |key, model| ids[model] << snapshot[key].to_i if snapshot[key].present? }
      config = snapshot["config"] || {}
      CONFIG_KEYS.each { |key, model| Array(config[key]).each { |id| ids[model] << id.to_i } }
      Array(snapshot["steps"]).each do |step|
        STEP_KEYS.each { |key, model| Array(step[key]).compact.each { |id| ids[model] << id.to_i } }
      end
    end

    def names(model, ids, workflow:)
      scope(model, workflow).where(id: ids).to_h do |record|
        [ record.id.to_s, { name: display_name(record), archived: archived?(record) } ]
      end
    end

    # A runner id is read through the workflow's tenant (TenantScope's Runner
    # rule), so a version that names another tenant's runner shows "#N
    # (deleted)", never that runner's name.
    def scope(model, workflow)
      return model.constantize unless model == "Runner"

      project = workflow&.runner_project
      project ? TenantScope.owned(Runner, project: project) : Runner.none
    end

    def display_name(record)
      record.try(:picker_name).presence || record.try(:display_name).presence ||
        record.try(:full_name).presence || record.try(:name).to_s
    end

    def archived?(record)
      return record.archived? if record.respond_to?(:archived?)

      record.respond_to?(:deleted_at) && record.deleted_at.present?
    end
  end
end
