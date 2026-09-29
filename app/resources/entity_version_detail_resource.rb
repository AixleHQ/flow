# frozen_string_literal: true

# A version with what the diff needs on both sides: its own snapshot, the one
# before it and the entity's current one. Snapshot keys are sent verbatim —
# they hold file paths, header names and column names, which camelizing would
# mangle — so the frontend reads them in the snake_case the snapshot is stored in.
class EntityVersionDetailResource < EntityVersionResource
  typelize_from EntityVersion
  preserve_keys :snapshot, :previous_snapshot, :current_snapshot, :references

  typelize "Record<string, unknown>"
  attribute :snapshot do |version|
    version.snapshot
  end

  typelize "Record<string, unknown> | null"
  attribute :previous_snapshot do |version|
    EntityVersion.where(versionable_type: version.versionable_type, versionable_id: version.versionable_id)
                 .where(number: ...version.number).order(number: :desc).pick(:snapshot)
  end

  typelize "Record<string, unknown>"
  attribute :current_snapshot do |version|
    Versions::Snapshot.dump(version.versionable)
  end

  typelize :number
  attribute :current_version_number do |version|
    version.versionable.current_version_number
  end

  # Names for the ids the snapshots mention, archived ones flagged, so the diff
  # can say "Tool: Deploy (archived)" instead of "tool_ids: [12]".
  typelize "Record<string, Record<string, { name: string; archived: boolean }>>"
  attribute :references do |version|
    Versions::ReferenceNames.for(version)
  end
end
