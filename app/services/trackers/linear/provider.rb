# frozen_string_literal: true

module Trackers
  module Linear
    # Linear as a tracker. A connection covers the teams picked when it was
    # made (`settings.linear_teams`); each team is a scope, keyed by its id. The
    # status is the issue's workflow state, which is what Linear's board columns
    # are, and the state's type gives its category.
    class Provider < Trackers::Provider
      CATEGORIES = {
        "triage" => "todo", "backlog" => "todo", "unstarted" => "todo", "started" => "in_progress",
        "completed" => "done", "canceled" => "canceled", "duplicate" => "canceled"
      }.freeze
      CLOSED_TYPES = %w[completed canceled duplicate].freeze
      ISSUE_KEY = /\A(?<team>[A-Z][A-Z0-9_]*)-\d+\z/i
      ISSUE_URL = %r{\Ahttps://linear\.app/(?<workspace>[^/]+)/issue/(?<key>[A-Z][A-Z0-9_]*-\d+)}i
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      UNASSIGNED = %w[none unassigned nobody].freeze
      FIELD_KEYS = %w[priority].freeze
      # Linear has no issue types; teams use labels for kinds of work.
      ISSUE_TYPE = "Issue"

      def serves_project?(project)
        integration.project_id == project.id
      end

      def scopes
        linear_teams.map { |t| Scope.new(id: t["id"].to_s, key: t["key"], name: t["name"].presence || t["key"]) }
      end

      def covers_scope?(scope_id)
        linear_teams.any? { |t| t["id"].to_s == scope_id.to_s }
      end

      def instance
        settings["organization_id"].to_s
      end

      # The OAuth app acts as itself. An API key acts as its owner, whose own
      # edits must not pass for Aixle's unless the account is kept for Aixle.
      def identity
        super if settings["dedicated_identity"] == true
      end

      # Linear writes a mention as @username, or as a link to the profile.
      def mentions_self?(text)
        login = identity&.dig("login")
        return super if login.blank? || text.blank?

        text.match?(/(?<![\w.-])@#{Regexp.escape(login)}(?![\w.-])/i) || text.include?("/profiles/#{login}") || super
      end

      def owns_reference?(scope_id, ref)
        key = key_in(ref.to_s.strip)
        key.present? && key.split("-").first.casecmp?(team_key(scope_id).to_s)
      end

      def issue_identifier(ref)
        issue_ref!(ref)
      rescue Error
        nil
      end

      def ensure_event_delivery!
        Subscriptions.new(integration).ensure!
      end

      def authentic_delivery?(request, raw_body, subscription)
        Webhooks.signed?(request, raw_body, subscription.secret)
      end

      def parse_delivery(payload, _subscription)
        Notifications.parse(payload, teams: linear_teams)
      end

      def delivery_id(request, _payload)
        request.headers["Linear-Delivery"].presence
      end

      def describe(scope_id)
        {
          statuses: states(scope_id).map { |s| Status.new(id: s[:id], name: s[:name], category: CATEGORIES[s[:type]]) },
          issue_types: [ { name: ISSUE_TYPE } ],
          fields: FIELD_KEYS,
          supports: { labels: true, multiple_assignees: false, native_query: false }
        }
      end

      # A delivery names the state it left by id only.
      def status_change(changes, issue)
        change = changes.find { |c| c[:field] == "status" }
        return unless change

        from = change[:from].presence || state_name(issue.scope_id, change[:from_id])
        to = change[:to].presence || issue.status&.name
        return if to.blank? || from == to

        { "field" => "status", "from" => status_value(issue.scope_id, from), "to" => status_value(issue.scope_id, to) }.compact
      end

      def get_issue(scope_id, ref)
        issue_from(scoped!(api.issue(issue_ref!(ref)), scope_id), scope_id)
      end

      def search_issues(scope_id, filter, cursor: nil, limit: nil)
        if filter[:native_query].present?
          raise Error.new("Linear has no query language here; use the structured filters", code: "validation_failed")
        end
        return Page.new(items: by_ids(scope_id, filter[:ids]), next_cursor: nil) if filter[:ids].present?

        result = api.issues(filter: filter_for(scope_id, filter), limit: (limit || 50).to_i.clamp(1, 100), cursor: cursor)
        issues = result[:issues].select { |raw| raw[:team_id] == scope_id.to_s }
        Page.new(items: issues.map { |raw| issue_from(raw, scope_id) }, next_cursor: result[:next_cursor])
      end

      def create_issue(scope_id, attributes)
        issue_type!(attributes[:type])
        input = { teamId: scope_id.to_s, title: attributes[:title].to_s, description: attributes[:description].presence,
                  assigneeId: attributes[:assignee].present? ? member_id!(scope_id, attributes[:assignee]) : nil,
                  labelIds: attributes[:labels].present? ? label_ids!(scope_id, attributes[:labels]) : nil }
        input.merge!(extra_fields(attributes[:fields]))
        issue_from(scoped!(api.create_issue(input.compact), scope_id), scope_id)
      end

      def update_issue(scope_id, ref, attributes)
        if attributes[:expected_revision].present?
          raise Error.new("Linear issues have no revision to compare; leave expected_revision out", code: "validation_failed")
        end

        current = scoped!(api.issue(issue_ref!(ref)), scope_id)
        input = { title: attributes[:title], description: attributes[:description] }.compact
        input[:labelIds] = label_ids!(scope_id, attributes[:labels]) if attributes.key?(:labels)
        input[:addedLabelIds] = label_ids!(scope_id, attributes[:labels_add]) if attributes[:labels_add].present?
        input[:removedLabelIds] = label_ids!(scope_id, attributes[:labels_remove]) if attributes[:labels_remove].present?
        input.merge!(extra_fields(attributes[:fields]))
        raise Error.new("No fields to update", code: "validation_failed") if input.empty?

        issue_from(api.update_issue(current[:id], input), scope_id)
      end

      # `status` is a workflow state of the team, by name or id.
      def transition_issue(scope_id, ref, status)
        current = scoped!(api.issue(issue_ref!(ref)), scope_id)
        return issue_from(current, scope_id) if current.dig(:state, :name).to_s.casecmp?(status.to_s.strip)

        all = states(scope_id)
        target = all.find { |s| s[:name].casecmp?(status.to_s.strip) || s[:id] == status.to_s }
        unless target
          names = all.pluck(:name)
          raise Error.new("'#{status}' is not a state of this team — states: #{names.join(', ')}",
                          code: "validation_failed", details: { allowed: names })
        end

        issue_from(api.update_issue(current[:id], { stateId: target[:id] }), scope_id)
      end

      def assign_issue(scope_id, ref, assignee)
        current = scoped!(api.issue(issue_ref!(ref)), scope_id)
        unassign = assignee.blank? || UNASSIGNED.include?(assignee.to_s.downcase)
        issue_from(api.update_issue(current[:id], { assigneeId: unassign ? nil : member_id!(scope_id, assignee) }), scope_id)
      end

      def list_users(scope_id, query:)
        api.members(scope_id, query: query.presence).map { |m| { id: m[:id], name: m[:display_name].presence || m[:name] } }
      end

      def list_comments(scope_id, ref, cursor: nil, limit: nil)
        current = scoped!(api.issue(issue_ref!(ref)), scope_id)
        result = api.comments(current[:id], limit: (limit || 50).to_i.clamp(1, 100), cursor: cursor)
        Page.new(items: result[:comments].map { |c| comment(c, current[:id]) }, next_cursor: result[:next_cursor])
      end

      def add_comment(scope_id, ref, body)
        current = scoped!(api.issue(issue_ref!(ref)), scope_id)
        comment(api.create_comment(current[:id], body), current[:id])
      end

      private

      def api
        @api ||= ::Linear::Api.for(integration)
      end

      def settings
        integration.settings.to_h
      end

      def linear_teams
        Array(settings["linear_teams"]).select { |t| t.is_a?(Hash) && t["id"].present? }
      end

      def team_key(scope_id)
        linear_teams.find { |t| t["id"].to_s == scope_id.to_s }&.dig("key")
      end

      def states(scope_id)
        Rails.cache.fetch([ "trackers", integration.id, scope_id.to_s, "linear_states" ], expires_in: 10.minutes) do
          api.states(scope_id)
        end
      end

      def state_name(scope_id, state_id)
        states(scope_id).find { |s| s[:id] == state_id.to_s }&.dig(:name) if state_id.present?
      end

      # An issue id is unique across the workspace; its team decides whether
      # this tracker may touch it.
      def scoped!(raw, scope_id)
        raise Error.new("Linear has no such issue, or this connection cannot see it", code: "not_found") if raw.nil?
        return raw if raw[:team_id] == scope_id.to_s

        raise Error.new("#{raw[:key] || raw[:id]} is not in this tracker's Linear team", code: "not_found")
      end

      def issue_ref!(ref)
        value = ref.to_s.strip
        key = key_in(value)
        return key if key
        return value.downcase if value.match?(UUID)

        raise Error.new("'#{ref}' is not a Linear issue identifier, id or URL", code: "validation_failed")
      end

      def key_in(value)
        match = ISSUE_URL.match(value)
        if match
          return unless match[:workspace].casecmp?(settings["url_key"].to_s)

          return match[:key].upcase
        end
        value.upcase if value.match?(ISSUE_KEY)
      end

      def by_ids(scope_id, ids)
        Array(ids).first(100).filter_map do |id|
          get_issue(scope_id, id)
        rescue Error => e
          raise unless e.code == "not_found"
        end
      end

      def issue_from(raw, scope_id)
        state = raw[:state]
        Issue.new(
          id: raw[:id], key: raw[:key], url: raw[:url], title: raw[:title], description: raw[:description], type: ISSUE_TYPE,
          status: state && Status.new(id: state[:id], name: state[:name], category: CATEGORIES[state[:type]]),
          assignees: [ raw.dig(:assignee, :display_name).presence || raw.dig(:assignee, :name) ].compact,
          labels: raw[:labels].pluck(:name), revision: nil, scope_id: scope_id.to_s, updated_at: raw[:updated_at],
          fields: { "state_type" => state&.dig(:type), "priority" => raw[:priority] }.compact
        )
      end

      def comment(raw, issue_id)
        Comment.new(id: raw[:id], issue_id: issue_id, author: raw[:author], body: raw[:body], created_at: raw[:created_at])
      end

      def issue_type!(type)
        return if type.blank? || type.to_s.strip.casecmp?(ISSUE_TYPE)

        raise Error.new("Linear has one issue type, #{ISSUE_TYPE}; use labels for kinds of work", code: "validation_failed")
      end

      def filter_for(scope_id, filter)
        issue_type!(filter[:type])
        clauses = [ { team: { id: { eq: scope_id.to_s } } } ]
        clauses << { state: { name: { eqIgnoreCase: filter[:status].to_s } } } if filter[:status].present?
        clauses << { state: { type: { nin: CLOSED_TYPES } } } if filter[:open_only]
        clauses << { assignee: { id: { eq: member_id!(scope_id, filter[:assignee]) } } } if filter[:assignee].present?
        clauses << { title: { containsIgnoreCase: filter[:text].to_s } } if filter[:text].present?
        Array(filter[:labels]).each { |label| clauses << { labels: { some: { name: { eqIgnoreCase: label.to_s } } } } }
        { and: clauses }
      end

      # Linear addresses people by id. A name, username or email is looked up
      # among the team's members and must match exactly one.
      def member_id!(scope_id, who)
        value = who.to_s.strip.delete_prefix("@")
        return value.downcase if value.match?(UUID)

        candidates = api.members(scope_id, query: value)
        exact = candidates.select { |m| [ m[:name], m[:display_name], m[:email] ].compact.any? { |v| v.casecmp?(value) } }
        match = exact.one? ? exact.first : (candidates.one? ? candidates.first : nil)
        return match[:id] if match

        names = candidates.map { |m| m[:display_name].presence || m[:name] }.first(10)
        raise Error.new("'#{who}' does not name one member of this team#{names.any? ? " — did you mean: #{names.join(', ')}" : ''}",
                        code: "validation_failed", details: { candidates: names })
      end

      def label_ids!(scope_id, names)
        wanted = Array(names).map(&:to_s).compact_blank
        return [] if wanted.empty?

        available = api.labels(scope_id)
        unknown = wanted.reject { |name| available.any? { |l| l[:name].casecmp?(name) } }
        if unknown.any?
          raise Error.new("No such label: #{unknown.join(', ')} — labels: #{available.pluck(:name).first(30).join(', ')}",
                          code: "validation_failed")
        end

        wanted.map { |name| available.find { |l| l[:name].casecmp?(name) }[:id] }.uniq
      end

      # Priority: 0 none, 1 urgent, 2 high, 3 medium, 4 low.
      def extra_fields(fields)
        priority = fields.to_h.transform_keys(&:to_s)["priority"]
        return {} if priority.blank?

        value = Integer(priority.to_s, exception: false)
        raise Error.new("fields.priority is 0 (none) to 4 (low)", code: "validation_failed") unless value&.between?(0, 4)

        { priority: value }
      end
    end
  end
end
