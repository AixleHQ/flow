# frozen_string_literal: true

# Every id an attribute holds must name a row of the record's own tenant, as
# TenantScope defines it. One rule for id arrays, association collections and
# single foreign keys, so a model declares what it references instead of
# hand-writing the check:
#
#   validates :input_asset_ids, tenant_ids: { model: Asset }
#   validates :tools, tenant_ids: { model: Tool, company: :company }, on: :create
#   validates :agent_id, tenant_ids: { model: Agent, project: :workflow_project, lenient: true, error_on: :agent }
#
# `project:` / `company:` name the record's methods that return its tenant
# (default: `project`, and that project's company). By default an id that does
# not exist is refused like a foreign one; `lenient: true` lets a deleted row's
# id through, for references that outlive what they point at. The message never
# says which of the two an id was.
class TenantIdsValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    ids = Array(value).map { |item| item.respond_to?(:id) ? item.id : item }.compact
    return if ids.empty?

    project = record.send(options.fetch(:project, :project))
    company = (options[:company] && record.send(options[:company])) || project&.company
    lookup = options[:lenient] ? :foreign_existing_ids : :foreign_ids
    foreign = TenantScope.public_send(lookup, options.fetch(:model), ids, project: project, company: company)
    return if foreign.empty?

    message = "must belong to this project (not found: #{foreign.sort.join(', ')})"
    key = options.fetch(:error_on, attribute)
    record.errors.add(key, key == attribute ? message : "#{attribute} #{message}")
  end
end
