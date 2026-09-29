# frozen_string_literal: true

# The tenant boundary for rows referenced by id: which rows of a class belong to
# a project (or, for a project-less session, to a company).
#
# Ownership only. It answers "may this id be referenced here?", not "should it
# be offered in a picker?" — no enabled/attachable filtering, so a Builder
# session may still carry the non-attachable meta tools, and a disabled MCP
# server stays a valid reference that the reader then skips. Platform-owned rows
# (code tools, internal MCP servers) belong to every tenant.
#
# Every path that stores an id list or reads one back resolves it through here,
# so a foreign id can neither be saved nor used.
module TenantScope
  module_function

  def owned(klass, project: nil, company: nil)
    company ||= project&.company

    case klass.name
    when "Tool"
      rel = Tool.where(source: "code")
      project ? rel.or(Tool.where(scope_type: "Project", scope_id: project.id)) : rel
    when "MCPServer"
      rel = MCPServer.where(kind: "internal")
      project ? rel.or(MCPServer.where(scope_type: "Project", scope_id: project.id)) : rel
    when "Asset"
      owned_assets(project, company)
    when "Integration"
      return Integration.none unless company

      rel = Integration.where(company_id: company.id, project_id: nil)
      project ? rel.or(Integration.where(company_id: company.id, project_id: project.id)) : rel
    when "Skill", "Repository", "ConfigItem", "Agent", "Workflow"
      project ? klass.where(scope_type: "Project", scope_id: project.id) : klass.none
    when "BoardColumn"
      project ? BoardColumn.joins(:board).where(boards: { project_id: project.id }) : BoardColumn.none
    else
      raise ArgumentError, "no tenant rule for #{klass.name}"
    end
  end

  # The ids in `ids` that do not belong to the tenant (unknown ids included).
  def foreign_ids(klass, ids, project: nil, company: nil)
    wanted = Array(ids).compact_blank.map(&:to_i).uniq
    return [] if wanted.empty?

    wanted - owned(klass, project: project, company: company).where(id: wanted).pluck(:id)
  end

  # Like #foreign_ids, but only ids that name an existing row. For id lists
  # that outlive the rows they point at (a step still listing a deleted tool):
  # a dangling id resolves to nothing, so refusing it would only block edits.
  def foreign_existing_ids(klass, ids, project: nil, company: nil)
    wanted = Array(ids).compact_blank.map(&:to_i).uniq
    return [] if wanted.empty?

    existing = klass.unscoped.where(id: wanted).pluck(:id)
    existing - owned(klass, project: project, company: company).where(id: existing).pluck(:id)
  end

  def owned_assets(project, company)
    if project
      Asset.where(scope_type: "Project", scope_id: project.id)
           .or(Asset.where(scope_type: "Company", scope_id: project.company_id))
    elsif company
      Asset.where(scope_type: "Company", scope_id: company.id)
    else
      Asset.none
    end
  end
  private_class_method :owned_assets
end
