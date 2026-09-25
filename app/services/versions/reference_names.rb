# frozen_string_literal: true

module Versions
  # Resolves the resource ids inside a workflow's snapshots to display names:
  # { "Tool" => { "12" => { name: "Deploy", archived: true } }, ... }. Rows that
  # no longer exist are simply absent, which the diff shows as "#12 (deleted)".
  module ReferenceNames
    STEP_KEYS = { "agent_id" => "Agent" }.merge(Snapshots::Workflow::STEP_REFERENCES).freeze
    CONFIG_KEYS = Snapshots::Workflow::CONFIG_REFERENCES

    module_function

    def for(version)
      return {} unless version.versionable_type == "Workflow"

      ids = Hash.new { |h, k| h[k] = Set.new }
      snapshots(version).each { |snapshot| collect(snapshot, ids) }
      ids.to_h { |model, set| [ model, names(model, set.to_a) ] }
    end

    def snapshots(version)
      scope = EntityVersion.where(versionable_type: "Workflow", versionable_id: version.versionable_id)
      [ version.snapshot, scope.where(number: ...version.number).order(number: :desc).pick(:snapshot),
        Snapshot.dump(version.versionable) ].compact
    end

    def collect(snapshot, ids)
      config = snapshot["config"] || {}
      CONFIG_KEYS.each { |key, model| Array(config[key]).each { |id| ids[model] << id.to_i } }
      Array(snapshot["steps"]).each do |step|
        STEP_KEYS.each { |key, model| Array(step[key]).compact.each { |id| ids[model] << id.to_i } }
      end
    end

    def names(model, ids)
      model.constantize.where(id: ids).to_h do |record|
        [ record.id.to_s, { name: display_name(record), archived: archived?(record) } ]
      end
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
