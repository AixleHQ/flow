# frozen_string_literal: true

# Id lists on a step or a workflow's config decide what a session is handed at
# launch — SessionConfigResolver loads them by raw id, so a foreign id would
# mount another tenant's MCP server (with its headers), repository or asset.
# The write is the only place ownership can be checked.
#
# Ownership, not availability: a tool whose integration is disconnected later
# is still this project's tool. Only ids being added are checked, so a record
# that already holds a stale id stays editable.
module ProjectOwnedReferences
  OWNERS = {
    agents: ->(project) { Agent.for_project(project) },
    tools: ->(project) { Tool.where(source: "code").or(Tool.where(scope_type: "Project", scope_id: project.id)) },
    skills: ->(project) { Skill.for_project(project) },
    mcp_servers: ->(project) { MCPServer.internal_servers.or(MCPServer.where(scope_type: "Project", scope_id: project.id)) },
    assets: ->(project) {
      Asset.where(scope_type: "Project", scope_id: project.id)
           .or(Asset.where(scope_type: "Company", scope_id: project.company_id))
    },
    repositories: ->(project) { Repository.for_project(project) },
    config_items: ->(project) { ConfigItem.for_project(project) }
  }.freeze

  # `lenient:` passes an id whose row is gone, as TenantScope.foreign_existing_ids
  # does: a resource list links only ids with a row, so such an id is dropped
  # from it rather than refused.
  def self.foreign_ids(project, kind, ids, lenient: false)
    ids = Array(ids).compact_blank.map(&:to_i).uniq
    return [] if ids.empty?
    return ids if project.nil?

    owners = OWNERS.fetch(kind).call(project)
    ids = owners.klass.unscoped.where(id: ids).pluck(:id) if lenient
    ids - owners.where(id: ids).pluck(:id)
  end

  private

  def validate_owned_ids(project, kind, attribute, before, after, label: nil, lenient: false)
    added = Array(after).compact_blank.map(&:to_i) - Array(before).compact_blank.map(&:to_i)
    foreign = ProjectOwnedReferences.foreign_ids(project, kind, added, lenient: lenient)
    return if foreign.empty?

    errors.add(attribute, [ label, "contains ids outside this project: #{foreign.sort.join(', ')}" ].compact.join(" "))
  end
end
