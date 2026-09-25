# frozen_string_literal: true

# The one write path for version history (docs/design/entity-versioning.md).
# Every explicit save, revert, archive and restore of a workflow, agent, skill,
# custom tool or MCP server goes through here, so the history is complete by
# construction rather than by callbacks — writes such as Positions.reorder! skip
# callbacks, and the snapshot is read back from the database after the change.
module Versions
  # Someone saved after the caller loaded the entity. The caller reloads and
  # sees the diff instead of silently overwriting the other change.
  class StaleVersion < StandardError
    attr_reader :current_number

    def initialize(current_number)
      @current_number = current_number
      super("Someone else saved a newer version (v#{current_number}). Reload to see their changes before saving.")
    end
  end

  # Archiving refused because active workflows still use the entity.
  class InUse < StandardError
    attr_reader :usages

    def initialize(record, usages)
      @usages = usages
      names = usages.map { |u| u[:step] ? "#{u[:workflow]} → #{u[:step]}" : u[:workflow] }
      super("Cannot archive #{record.class.model_name.human.downcase} — it is used by: #{names.join(', ')}")
    end
  end

  # Who made a change and through which surface. `session` is the terminal
  # session an agent acted from (Aixle Builder), so its edits are told apart
  # from the person the session belongs to.
  Actor = Data.define(:user, :source, :session) do
    def self.ui(user) = new(user: user, source: "ui", session: nil)
    def self.api(user) = new(user: user, source: "api", session: nil)
    def self.system(user = nil) = new(user: user, source: "system", session: nil)

    def self.mcp(user, session: nil)
      new(user: user, source: session ? "builder" : "mcp", session: session)
    end
  end

  module_function

  # Yields the (locked) record for the caller to change, then records a version
  # when the result differs from the latest one. A new record gets version 1.
  # Returns the version written, or nil for a save that changed nothing.
  def save!(record, actor:, base_version: nil, metadata: {})
    transaction_for(record) do
      creating = record.new_record?
      prepare!(record, base_version) unless creating
      yield record
      snapshot = Snapshot.dump(record)
      next nil if !creating && snapshot == record.latest_version&.snapshot

      write!(record, creating ? "created" : "saved", snapshot, actor, metadata: metadata)
    end
  end

  # Applies an earlier version's snapshot to the entity and records the result
  # as the newest version.
  def revert!(record, to:, actor:, base_version: nil)
    raise ArgumentError, "version #{to.id} belongs to another entity" unless to.versionable == record

    record_event!(record, "reverted", actor, base_version, restored_from: to) do
      Snapshot.restore!(record, to.snapshot)
    end
  end

  def archive!(record, actor:, base_version: nil)
    usages = References.usages(record)
    raise InUse.new(record, usages) if usages.any?

    metadata = {}
    if record.is_a?(Workflow)
      metadata["disabled_trigger_ids"] = record.trigger_bindings.where(enabled: true).pluck(:id)
    end
    record_event!(record, "archived", actor, base_version, metadata: metadata) { record.archive! }
  end

  # `enable_trigger_ids` (workflows only): the triggers archiving switched off
  # to switch back on — see the archived version's `disabled_trigger_ids`.
  def restore!(record, actor:, enable_trigger_ids: [])
    record_event!(record, "restored", actor, nil) do
      record.is_a?(Workflow) ? record.unarchive!(enable_trigger_ids: enable_trigger_ids) : record.unarchive!
    end
  end

  def record_event!(record, event, actor, base_version, metadata: {}, restored_from: nil)
    transaction_for(record) do
      prepare!(record, base_version)
      yield record
      write!(record, event, Snapshot.dump(record), actor, metadata: metadata, restored_from: restored_from)
    end
  end

  def transaction_for(record, &)
    record.class.transaction(&)
  end

  # Locks the row (reloading it), refuses a stale base version, and gives an
  # entity that predates version history a baseline to diff its first change
  # against.
  def prepare!(record, base_version)
    record.lock!
    raise StaleVersion, record.current_version_number if base_version && base_version.to_i != record.current_version_number
    return if record.current_version_number.positive?

    write!(record, "created", Snapshot.dump(record), Actor.system, metadata: { "baseline" => true })
  end

  def write!(record, event, snapshot, actor, metadata: {}, restored_from: nil)
    number = record.current_version_number + 1
    version = EntityVersion.create!(
      versionable: record, number: number, event: event, snapshot: snapshot,
      snapshot_format: Snapshot.for(record).format, restored_from: restored_from,
      author: actor.user, source: actor.source, terminal_session: actor.session,
      metadata: metadata, project_id: record.try(:project_id), company_id: record.try(:company_id)
    )
    record.update_column(:current_version_number, number)
    record.association(:entity_versions).reset
    version
  end
end
