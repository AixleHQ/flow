# frozen_string_literal: true

# One entry in the Versions timeline. The snapshot itself is served only by
# EntityVersionDetailResource: a skill snapshot carries its whole directory, and
# a page of twenty of those is not what a timeline needs.
class EntityVersionResource < ApplicationResource
  attributes :id, :number, :versionable_type, :versionable_id, :terminal_session_id, :created_at

  typelize %w[created saved reverted archived restored]
  attribute :event do |version|
    version.event.to_s
  end

  typelize %w[ui api mcp builder system]
  attribute :source do |version|
    version.source.to_s
  end

  typelize "{ id: number; name: string } | null"
  attribute :author do |version|
    version.author && { id: version.author.id, name: version.author.name }
  end

  typelize "number | null"
  attribute :restored_from_number do |version|
    version.restored_from&.number
  end

  typelize :boolean
  attribute :baseline do |version|
    version.baseline?
  end

  typelize "number | null"
  attribute :duplicated_from_id do |version|
    version.metadata["duplicated_from"]
  end

  typelize "number[]"
  attribute :disabled_trigger_ids do |version|
    Array(version.metadata["disabled_trigger_ids"])
  end
end
