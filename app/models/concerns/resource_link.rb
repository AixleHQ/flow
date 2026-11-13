# frozen_string_literal: true

# One entry of a step's or a workflow's resource list. Exactly one resource
# column is set, and its foreign key drops the entry when the resource is deleted.
#
# Every read of a list comes from here. Writes still go to the jsonb id lists
# (`steps.repository_ids`, `workflows.config["base_repository_ids"]`, …), which
# Step and Workflow mirror here on save, so pods of the previous release that
# read them stay right; the lists go in the release after this one.
module ResourceLink
  extend ActiveSupport::Concern

  COLUMNS = {
    tool_ids: :tool_id, skill_ids: :skill_id, mcp_server_ids: :mcp_server_id,
    asset_ids: :asset_id, repository_ids: :repository_id, config_item_ids: :config_item_id
  }.freeze

  included do
    belongs_to :tool, optional: true
    belongs_to :skill, optional: true
    belongs_to :mcp_server, class_name: "MCPServer", optional: true
    belongs_to :asset, optional: true
    belongs_to :repository, optional: true
    belongs_to :config_item, optional: true
  end

  class_methods do
    # Makes the owner's links in `column` the given ids, in their order. An id
    # whose row is gone has nothing to link to and is skipped.
    def replace!(owner, column, ids)
      ids = Array(ids).compact_blank.map(&:to_i).select(&:positive?).uniq
      target = reflect_on_association(column.to_s.delete_suffix("_id")).klass
      present = target.where(id: ids).pluck(:id).to_set
      rows = ids.select { |id| present.include?(id) }
                .each_with_index.map { |id, position| { owner_column => owner.id, column => id, position: position } }

      transaction do
        where(owner_column => owner.id).where.not(column => nil).delete_all
        insert_all!(rows) if rows.any?
      end
    end
  end
end
