# frozen_string_literal: true

module Trackers
  module AzureDevops
    # Azure Boards as a tracker, over the existing connection and
    # ::AzureDevops::WorkItemService. Credentials, the capability profile and the
    # project allow-list stay where they are: WorkItemService resolves every call
    # through CredentialProvider.
    class Provider < Trackers::Provider
      CATEGORIES = {
        "Proposed" => "todo", "InProgress" => "in_progress", "Resolved" => "in_progress",
        "Completed" => "done", "Removed" => "canceled"
      }.freeze
      ISSUE_URL = %r{\Ahttps?://[^/]+/(?<organization>[^/]+)/(?<project>[^/]+)/_workitems/edit/(?<id>\d+)}i
      FIELD_KEYS = %w[area_path iteration_path priority acceptance_criteria repro_steps].freeze

      def serves_project?(project)
        integration.project_id == project.id
      end

      def scopes
        names = integration.azure_project_names
        integration.azure_project_ids.map { |id| Scope.new(id: id, key: nil, name: names[id].presence || id) }
      end

      def covers_scope?(scope_id)
        integration.azure_project_selected?(scope_id.to_s)
      end

      def instance
        "#{::AzureDevops::AppConfig.api_host}/#{integration.azure_organization_slug}".downcase
      end

      def ensure_event_delivery!
        return unless ::AzureDevops::AppConfig.webhooks_enabled?

        ::AzureDevops::SubscriptionService.new(integration).ensure_all!(event_types: AzureDevopsSubscription::TRACKER_EVENT_TYPES)
      end

      def owns_reference?(scope_id, ref)
        match = ISSUE_URL.match(ref.to_s)
        return false unless match
        return false unless match[:organization].casecmp?(integration.azure_organization_slug.to_s)

        project = CGI.unescape(match[:project])
        project.casecmp?(scope_id.to_s) || project.casecmp?(integration.azure_project_names[scope_id.to_s].to_s)
      end

      def issue_identifier(ref)
        work_item_id!(ref).to_s
      rescue Error
        nil
      end

      # `statuses` are the board's columns — what an issue moves between on the
      # board, and what triggers match. `states` are the workflow states a
      # transition sets. Without a board (or when Azure will not list it) the
      # states stand in for the columns.
      def describe(scope_id)
        translate do
          types = work_items.work_item_types(project_id: scope_id)
          states = types.flat_map { |t| t[:states] }.uniq { |s| s[:name] }.map { |s| state_status(s[:name], s[:category]) }
          {
            statuses: board_statuses(scope_id).presence || states,
            states: states,
            issue_types: types.map { |t| { name: t[:name], statuses: t[:states].pluck(:name), required_fields: t[:required_fields] } },
            fields: FIELD_KEYS,
            supports: { labels: true, multiple_assignees: false, native_query: false }
          }
        end
      end

      # A card moving between board columns is the status change. A state change
      # alone counts only for a work item that is on no board; otherwise the card
      # moved too, and its column change is the one reported.
      def status_change(changes, issue)
        column = changes.find { |c| c[:field] == "board_column" }
        state = changes.find { |c| c[:field] == "state" }
        return if column.nil? && (state.nil? || issue.fields["board_column"].present?)

        base = column || state
        category = issue.status&.category
        {
          "field" => "status",
          "from" => status_value(issue.scope_id, base[:from], category: column ? nil : state_category_for(issue.scope_id, base[:from])),
          "to" => status_value(issue.scope_id, base[:to], category: category),
          "state" => state && { "from" => state[:from], "to" => state[:to] }.compact
        }.compact
      end

      def get_issue(scope_id, ref)
        translate { issue_from(work_items.get(work_item_id!(ref), project_id: scope_id), scope_id) }
      end

      def search_issues(scope_id, filter, cursor: nil, limit: nil)
        if filter[:native_query].present?
          raise Error.new("Azure Boards does not accept a native query; use the structured filters", code: "validation_failed")
        end

        translate do
          result = work_items.query(filters: query_filters(filter), limit: limit, cursor: cursor, project_id: scope_id)
          Page.new(items: result[:work_items].map { |item| issue_from(item, scope_id) }, next_cursor: result[:next_cursor])
        end
      end

      def create_issue(scope_id, attributes)
        type = attributes[:type].presence
        raise Error.new("type is required — tracker_describe lists this project's issue types", code: "validation_failed") unless type

        translate do
          written(work_items.create(type: type, fields: write_fields(attributes), project_id: scope_id), scope_id)
        end
      end

      def update_issue(scope_id, ref, attributes)
        translate do
          current = work_items.get(work_item_id!(ref), project_id: scope_id)
          fields = write_fields(attributes, current_labels: labels_of(current))
          raise Error.new("No fields to update", code: "validation_failed") if fields.empty?

          updated = work_items.update(current[:id], fields: fields, expected_revision: attributes[:expected_revision],
                                                    project_id: scope_id)
          written(updated, scope_id)
        end
      end

      def transition_issue(scope_id, ref, status)
        translate do
          current = work_items.get(work_item_id!(ref), project_id: scope_id)
          allowed = work_items.work_item_types(project_id: scope_id).find { |t| t[:name] == current[:type] }&.dig(:states)&.pluck(:name) || []
          target = allowed.find { |name| name.casecmp?(status.to_s) }
          unless target
            raise Error.new("'#{status}' is not a state of #{current[:type]} — allowed: #{allowed.join(', ')}. " \
                            "Azure moves a card between board columns through the state its column maps to.",
                            code: "validation_failed", details: { allowed: allowed })
          end

          written(work_items.update(current[:id], fields: { state: target }, project_id: scope_id), scope_id)
        end
      end

      def assign_issue(scope_id, ref, assignee)
        translate do
          current = work_items.get(work_item_id!(ref), project_id: scope_id)
          written(work_items.update(current[:id], fields: { assigned_to: assignee.to_s }, project_id: scope_id), scope_id)
        end
      end

      def list_comments(scope_id, ref, cursor: nil, limit: nil)
        translate do
          id = work_items.get(work_item_id!(ref), project_id: scope_id)[:id]
          result = work_items.comments(id, limit: limit, cursor: cursor, project_id: scope_id)
          comments = result[:comments].map do |c|
            Comment.new(id: c[:id].to_s, issue_id: id.to_s, author: c[:author], body: c[:text], created_at: c[:created_at])
          end
          Page.new(items: comments, next_cursor: result[:next_cursor])
        end
      end

      def add_comment(scope_id, ref, body)
        translate do
          id = work_items.get(work_item_id!(ref), project_id: scope_id)[:id]
          comment = work_items.add_comment(id, text: body, project_id: scope_id)
          Comment.new(id: comment[:id].to_s, issue_id: id.to_s, author: nil, body: body, created_at: comment[:created_at])
        end
      end

      private

      def work_items
        @work_items ||= ::AzureDevops::WorkItemService.new(integration)
      end

      # Connecting and Test connection read the identity from connectionData;
      # the connection's own writes (System.ChangedBy on what it just changed)
      # keep it current where that could not be asked.
      def remember_identity(item)
        by = item[:changed_by]
        return if by.blank? || by[:id].blank? || identity&.dig("id") == by[:id]

        me = { "id" => by[:id], "name" => by[:display_name] }.compact
        integration.update_column(:settings, integration.settings.to_h.merge("tracker_identity" => me))
      end

      def written(item, scope_id)
        remember_identity(item)
        issue_from(item, scope_id)
      end

      def translate
        yield
      rescue ::AzureDevops::OutcomeUnknown => e
        raise Error::OutcomeUnknown, e.message
      rescue ::AzureDevops::Conflict => e
        raise Error::Conflict.new(e.message, details: e.details)
      rescue ::AzureDevops::Error => e
        raise Error.new(e.message, code: e.code, details: e.details)
      end

      def work_item_id!(ref)
        value = ref.to_s.strip
        id = ISSUE_URL.match(value)&.[](:id) || value.delete_prefix("#")
        raise Error.new("'#{ref}' is not an Azure Boards work item id or URL", code: "validation_failed") unless id.match?(/\A\d+\z/)

        id.to_i
      end

      def query_filters(filter)
        {
          ids: filter[:ids].presence&.map(&:to_i),
          type: filter[:type],
          state: filter[:status],
          assigned_to: filter[:assignee],
          title_contains: filter[:text],
          tag: Array(filter[:labels]).first,
          open_only: filter[:open_only]
        }.compact_blank
      end

      # Tracker attributes → WorkItemService field keys. Labels are Azure tags, one
      # semicolon-separated field, so adding or removing one rewrites the set.
      def write_fields(attributes, current_labels: [])
        fields = attributes.slice(:title, :description).compact
        fields[:assigned_to] = attributes[:assignee] if attributes.key?(:assignee)
        labels = next_labels(attributes, current_labels)
        fields[:tags] = labels.join("; ") if labels
        fields.merge!(attributes[:fields].to_h.symbolize_keys.slice(*FIELD_KEYS.map(&:to_sym)))
        fields.compact
      end

      def next_labels(attributes, current)
        return Array(attributes[:labels]) if attributes.key?(:labels)
        return nil unless attributes.key?(:labels_add) || attributes.key?(:labels_remove)

        removed = Array(attributes[:labels_remove]).map(&:downcase)
        (current.reject { |l| removed.include?(l.downcase) } + Array(attributes[:labels_add])).uniq(&:downcase)
      end

      def labels_of(item)
        item[:tags].to_s.split(";").map(&:strip).compact_blank
      end

      def state_status(name, category = nil)
        Status.new(id: name, name: name, category: CATEGORIES[category])
      end

      def board_statuses(scope_id)
        work_items.board_columns(project_id: scope_id).map { |c| Status.new(id: c[:name], name: c[:name], category: c[:category]) }
      rescue ::AzureDevops::Error => e
        Rails.logger.info("[Trackers::AzureDevops] board columns unavailable for #{scope_id}: #{e.code}")
        []
      end

      # The column the card sits in, categorized by the state behind it — a
      # column named "Ready for AI" says nothing, the state it maps to does.
      def issue_from(item, scope_id)
        name = item[:board_column].presence || item[:state]
        Issue.new(
          id: item[:id].to_s, key: item[:id].to_s, url: item[:url], title: item[:title],
          description: item[:description], type: item[:type],
          status: name && Status.new(id: name, name: name, category: state_category_for(scope_id, item[:state])),
          assignees: Array(item[:assigned_to]), labels: labels_of(item), revision: item[:rev],
          scope_id: scope_id.to_s, updated_at: item[:changed_at],
          fields: { "state" => item[:state], "board_column" => item[:board_column] }
                    .merge(item.slice(:area_path, :iteration_path).transform_keys(&:to_s)).compact
        )
      end

      def state_category_for(scope_id, state)
        return if state.blank?

        states = Rails.cache.fetch([ "trackers", integration.id, scope_id.to_s, "state_categories" ], expires_in: 10.minutes) do
          work_items.work_item_types(project_id: scope_id).flat_map { |t| t[:states] }
                    .to_h { |s| [ s[:name].to_s.downcase, CATEGORIES[s[:category]] ] }
        end
        states[state.to_s.downcase]
      rescue ::AzureDevops::Error
        nil
      end
    end
  end
end
