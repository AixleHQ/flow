# frozen_string_literal: true

module Trackers
  module AzureDevops
    # Azure Service Hook `workitem.*` resources → Trackers::Notification.
    #
    # The shapes differ by event: in `workitem.updated` the resource is the
    # UPDATE — `id` is the update number, `workItemId` the work item, and each
    # changed field is `{oldValue, newValue}` — while `created` and `commented`
    # carry the work item itself. A commented event names no comment id; the text
    # is System.History.
    module Notifications
      EVENT_KINDS = {
        "workitem.created" => :issue_created,
        "workitem.updated" => :issue_updated,
        "workitem.commented" => :comment_created
      }.freeze
      FIELDS = { "System.BoardColumn" => "board_column", "System.State" => "state", "System.AssignedTo" => "assignee" }.freeze

      def self.parse(event_type, resource, scope_id:)
        kind = EVENT_KINDS[event_type.to_s]
        resource = resource.to_h
        issue_id = resource["workItemId"].presence || (kind == :issue_updated ? nil : resource["id"])
        return if kind.nil? || issue_id.blank?

        fields = resource["fields"].to_h
        Notification.build(
          kind: kind, scope_id: scope_id, issue_id: issue_id,
          comment_text: (fields["System.History"].presence || resource["System.History"].presence if kind == :comment_created),
          changes: kind == :issue_updated ? changes(fields) : [],
          actor: actor(resource, fields), revision: resource["rev"],
          occurred_at: value(fields["System.ChangedDate"])
        )
      end

      def self.changes(fields)
        FIELDS.filter_map do |ref, field|
          change = fields[ref]
          next unless change.is_a?(Hash) && (change.key?("newValue") || change.key?("oldValue"))

          { field: field, from: identity_name(change["oldValue"]), to: identity_name(change["newValue"]) }
        end
      end

      def self.actor(resource, fields)
        by = resource["revisedBy"].presence || value(fields["System.ChangedBy"])
        return {} if by.blank?
        return { name: identity_name(by) } unless by.is_a?(Hash)

        { id: by["id"], name: by["displayName"] || by["uniqueName"] }.compact
      end

      # A field in `workitem.updated` is {oldValue, newValue}; elsewhere the value itself.
      def self.value(field)
        field.is_a?(Hash) && field.key?("newValue") ? field["newValue"] : field
      end

      # Identity fields arrive as identity objects or as "Display Name <unique
      # name>" strings, whose unique name is an email or, for a service
      # principal, a GUID. The display name is what users and filters compare.
      def self.identity_name(value)
        return value["displayName"] || value["uniqueName"] if value.is_a?(Hash)
        return value unless value.is_a?(String)

        value.sub(/\s*<[^<>]*>\z/, "").presence || value
      end
    end
  end
end
