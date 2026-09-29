# frozen_string_literal: true

# One immutable entry in an entity's history: a full snapshot of a workflow,
# agent, skill, custom tool or MCP server as it stood after an explicit save,
# revert, archive or restore. Written only by Versions — see
# docs/design/entity-versioning.md.
class EntityVersion < ApplicationRecord
  extend Enumerize

  VERSIONABLE_TYPES = %w[Workflow Agent Skill Tool MCPServer].freeze

  belongs_to :versionable, polymorphic: true
  belongs_to :author, class_name: "User", optional: true
  belongs_to :terminal_session, optional: true
  belongs_to :restored_from, class_name: "EntityVersion", optional: true

  enumerize :event, in: %i[created saved reverted archived restored], predicates: true
  enumerize :source, in: %i[ui api mcp builder system]

  validates :versionable_type, inclusion: { in: VERSIONABLE_TYPES }
  validates :number, numericality: { greater_than: 0 }

  scope :newest_first, -> { order(number: :desc) }

  def readonly?
    persisted?
  end

  def baseline?
    metadata["baseline"] == true
  end
end
