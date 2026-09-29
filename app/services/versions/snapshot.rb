# frozen_string_literal: true

module Versions
  # Finds the snapshot serializer for a versioned record. A snapshot is plain
  # JSON (string keys, ISO times), so a freshly dumped hash compares equal to
  # the jsonb one read back from entity_versions.
  module Snapshot
    SERIALIZERS = {
      "Agent" => "Versions::Snapshots::Agent",
      "Skill" => "Versions::Snapshots::Skill",
      "Tool" => "Versions::Snapshots::Tool",
      "MCPServer" => "Versions::Snapshots::MCPServer",
      "Workflow" => "Versions::Snapshots::Workflow"
    }.freeze

    module_function

    def for(record_or_class)
      klass = record_or_class.is_a?(Class) ? record_or_class : record_or_class.class
      SERIALIZERS.fetch(klass.base_class.name).constantize
    end

    def dump(record)
      JSON.parse(JSON.generate(self.for(record).dump(record)))
    end

    def restore!(record, snapshot)
      self.for(record).restore!(record, snapshot)
    end
  end
end
