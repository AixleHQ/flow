# frozen_string_literal: true

module Trackers
  module Jira
    # Jira Cloud as a tracker. A connection covers the Jira projects picked when
    # it was made (`settings.jira_projects`); each is a tracker scope, keyed by
    # the project's numeric id, which survives a key rename.
    #
    # As on Azure, the status is the column the issue sits in on the project's
    # board, and the workflow status behind it is `fields.state`. A project with
    # no board has only its workflow statuses.
    class Provider < Trackers::Provider
      CATEGORIES = { "new" => "todo", "indeterminate" => "in_progress", "done" => "done" }.freeze
      ISSUE_KEY = /\A(?<project>[A-Z][A-Z0-9_]*)-\d+\z/i
      ACCOUNT_ID = /\A(?:[0-9a-f]{24}|[0-9a-z]+:[0-9a-f-]{36}(?::[0-9a-f-]{36})?)\z/i
      FIELD_KEYS = %w[priority due_date parent components].freeze
      UNASSIGNED = %w[none unassigned nobody].freeze

      def serves_project?(project)
        integration.project_id == project.id
      end

      def scopes
        jira_projects.map { |p| Scope.new(id: p["id"].to_s, key: p["key"], name: p["name"].presence || p["key"]) }
      end

      def covers_scope?(scope_id)
        jira_projects.any? { |p| p["id"].to_s == scope_id.to_s }
      end

      def instance
        settings["cloud_id"].to_s
      end

      # A 3LO connection acts as the person who connected it, so their own edits
      # would pass for Aixle's. Only an account kept for Aixle is an identity.
      def identity
        super if settings["dedicated_identity"] == true
      end

      def owns_reference?(scope_id, ref)
        key = issue_key_in(ref.to_s)
        key.present? && key.split("-").first.casecmp?(project_key(scope_id).to_s)
      end

      def ensure_event_delivery!
        Subscriptions.new(integration).ensure!
      end

      def authentic_delivery?(request, raw_body, subscription)
        Webhooks.signed?(request, raw_body, subscription.secret)
      end

      def parse_delivery(payload, _subscription)
        Notifications.parse(payload, projects: jira_projects)
      end

      def delivery_id(request, _payload)
        request.headers["X-Atlassian-Webhook-Identifier"].presence
      end

      # `statuses` are the columns of the project's board; `states` the workflow
      # statuses a transition can set.
      def describe(scope_id)
        translate do
          states = project_statuses(scope_id)
          columns = board_columns(scope_id, states)
          project = api.project(scope_id)
          {
            statuses: columns.map { |c| c[:status] }.presence || states.values.uniq(&:name),
            states: states.values.uniq(&:name),
            issue_types: project[:issue_types].map do |type|
              { name: type[:name], subtask: type[:subtask], statuses: type_statuses(scope_id)[type[:name]] }.compact
            end,
            fields: FIELD_KEYS,
            supports: { labels: true, multiple_assignees: false, native_query: true }
          }
        end
      end

      # A move between columns is the status change; a status change inside one
      # column moved nothing on the board and is not reported.
      def status_change(changes, issue)
        change = changes.find { |c| c[:field] == "status" }
        return unless change

        columns = column_index(issue.scope_id)
        return super if columns.empty?

        from = columns[change[:from_id].to_s] || change[:from]
        to = columns[change[:to_id].to_s] || issue.status&.name || change[:to]
        return if from.present? && from == to

        {
          "field" => "status", "from" => status_value(issue.scope_id, from), "to" => status_value(issue.scope_id, to),
          "state" => { "from" => change[:from], "to" => change[:to] }.compact
        }.compact
      end

      def get_issue(scope_id, ref)
        translate { issue_from(scoped!(api.issue(issue_ref!(ref)), scope_id), scope_id) }
      end

      def search_issues(scope_id, filter, cursor: nil, limit: nil)
        translate do
          jql, order = jql_for(scope_id, filter)
          result = api.search(jql: "#{jql} ORDER BY #{order}", limit: (limit || 50).to_i.clamp(1, 100), cursor: cursor)
          # A native query is ANDed in brackets, but a result outside the project
          # is dropped whatever the query said.
          issues = result[:issues].select { |raw| raw.dig(:project, :id) == scope_id.to_s }
          Page.new(items: issues.map { |raw| issue_from(raw, scope_id) }, next_cursor: result[:next_cursor])
        end
      end

      def create_issue(scope_id, attributes)
        type = attributes[:type].presence
        raise Error.new("type is required — tracker_describe lists this project's issue types", code: "validation_failed") unless type

        translate do
          fields = { project: { id: scope_id.to_s }, issuetype: { name: type }, summary: attributes[:title].to_s }
          fields[:description] = attributes[:description] if attributes[:description].present?
          fields[:labels] = Array(attributes[:labels]) if attributes[:labels].present?
          fields[:assignee] = { accountId: account_id!(scope_id, attributes[:assignee]) } if attributes[:assignee].present?
          fields.merge!(extra_fields(attributes[:fields]))
          created = api.create_issue(fields)
          issue_from(api.issue(created[:id]), scope_id)
        end
      end

      def update_issue(scope_id, ref, attributes)
        if attributes[:expected_revision].present?
          raise Error.new("Jira issues have no revision to compare; leave expected_revision out", code: "validation_failed")
        end

        translate do
          current = scoped!(api.issue(issue_ref!(ref)), scope_id)
          fields = { summary: attributes[:title], description: attributes[:description] }.compact
          fields[:labels] = Array(attributes[:labels]) if attributes.key?(:labels)
          fields.merge!(extra_fields(attributes[:fields]))
          labels = Array(attributes[:labels_add]).map { |l| { add: l } } + Array(attributes[:labels_remove]).map { |l| { remove: l } }
          raise Error.new("No fields to update", code: "validation_failed") if fields.empty? && labels.empty?

          api.update_issue(current[:id], fields: fields, update: labels.any? ? { labels: labels } : {})
          issue_from(api.issue(current[:id]), scope_id)
        end
      end

      # `status` may name a workflow status, a transition, or a board column — a
      # column is reached through any transition into one of its statuses.
      def transition_issue(scope_id, ref, status)
        translate do
          current = scoped!(api.issue(issue_ref!(ref)), scope_id)
          issue = issue_from(current, scope_id)
          next issue if [ issue.status&.name, current.dig(:status, :name) ].compact.any? { |name| name.casecmp?(status.to_s) }

          available = api.transitions(current[:id])
          target = pick_transition(scope_id, available, status.to_s)
          unless target
            reachable = available.map { |t| t.dig(:to, :name) }.uniq
            raise Error.new("'#{status}' cannot be reached from #{current.dig(:status, :name)} — reachable: #{reachable.join(', ')}",
                            code: "validation_failed", details: { allowed: reachable })
          end

          api.transition(current[:id], target[:id])
          issue_from(api.issue(current[:id]), scope_id)
        end
      end

      def assign_issue(scope_id, ref, assignee)
        translate do
          current = scoped!(api.issue(issue_ref!(ref)), scope_id)
          unassign = assignee.blank? || UNASSIGNED.include?(assignee.to_s.downcase)
          api.assign(current[:id], unassign ? nil : account_id!(scope_id, assignee))
          issue_from(api.issue(current[:id]), scope_id)
        end
      end

      def list_users(scope_id, query:)
        translate do
          api.assignable_users(project_key: project_key(scope_id), query: query.to_s).map { |u| u.slice(:id, :name) }
        end
      end

      def list_comments(scope_id, ref, cursor: nil, limit: nil)
        translate do
          current = scoped!(api.issue(issue_ref!(ref)), scope_id)
          result = api.comments(current[:id], limit: (limit || 50).to_i.clamp(1, 100), cursor: cursor)
          comments = result[:comments].map do |c|
            Comment.new(id: c[:id], issue_id: current[:id], author: c[:author], body: c[:body], created_at: c[:created_at])
          end
          Page.new(items: comments, next_cursor: result[:next_cursor])
        end
      end

      def add_comment(scope_id, ref, body)
        translate do
          current = scoped!(api.issue(issue_ref!(ref)), scope_id)
          c = api.add_comment(current[:id], body.to_s)
          Comment.new(id: c[:id], issue_id: current[:id], author: c[:author], body: c[:body], created_at: c[:created_at])
        end
      end

      private

      def api
        @api ||= ::Jira::Api.for(integration)
      end

      def settings
        integration.settings.to_h
      end

      def jira_projects
        Array(settings["jira_projects"]).select { |p| p.is_a?(Hash) && p["id"].present? }
      end

      def project_key(scope_id)
        jira_projects.find { |p| p["id"].to_s == scope_id.to_s }&.dig("key")
      end

      def translate
        yield
      rescue ::Jira::Error::OutcomeUnknown => e
        raise Error::OutcomeUnknown, e.message
      rescue ::Jira::Error => e
        raise Error::Conflict.new(e.message, details: e.details) if e.code == "conflict"

        raise Error.new(e.message, code: e.code, details: e.details)
      end

      # An issue id is only unique per site; which project it is in is what
      # decides whether this tracker may touch it.
      def scoped!(raw, scope_id)
        return raw if raw.dig(:project, :id) == scope_id.to_s

        raise ::Jira::Error.new("#{raw[:key] || raw[:id]} is not in this tracker's Jira project", code: "not_found")
      end

      def issue_ref!(ref)
        value = ref.to_s.strip
        key = issue_key_in(value)
        return key if key
        return value if value.match?(/\A\d+\z/)

        raise Error.new("'#{ref}' is not a Jira issue key, id or URL", code: "validation_failed")
      end

      def issue_key_in(value)
        candidate = if value.match?(%r{\Ahttps?://}i)
          uri = URI.parse(value)
          return unless uri.host.to_s.casecmp?(site_host.to_s)

          uri.path[%r{/browse/([^/?#]+)}, 1] || CGI.parse(uri.query.to_s)["selectedIssue"]&.first
        else
          value
        end
        candidate.to_s.upcase if candidate.to_s.match?(ISSUE_KEY)
      rescue URI::InvalidURIError
        nil
      end

      def site_host
        URI.parse(settings["site_url"].to_s).host
      rescue URI::InvalidURIError
        nil
      end

      def issue_from(raw, scope_id)
        columns = column_index(scope_id)
        state = raw[:status]
        column = state && columns[state[:id]]
        name = column || state&.dig(:name)
        Issue.new(
          id: raw[:id], key: raw[:key], url: browse_url(raw[:key]), title: raw[:summary],
          description: raw[:description], type: raw[:type],
          status: name && Status.new(id: column || state[:id], name: name,
                                     category: column ? status_category(scope_id, column) : CATEGORIES[state[:category]]),
          assignees: [ raw.dig(:assignee, :name) ].compact, labels: raw[:labels], revision: nil,
          scope_id: scope_id.to_s, updated_at: raw[:updated_at],
          fields: {
            "state" => state&.dig(:name), "board_column" => column, "priority" => raw[:priority], "due_date" => raw[:due_date],
            "parent" => raw[:parent], "components" => raw[:components].presence, "assignee_id" => raw.dig(:assignee, :id)
          }.compact
        )
      end

      def browse_url(key)
        site = settings["site_url"].to_s.chomp("/")
        "#{site}/browse/#{key}" if site.present? && key.present?
      end

      # status id => Status, across the project's issue types.
      def project_statuses(scope_id)
        statuses_of(scope_id).flat_map { |t| t[:statuses] }.to_h do |s|
          [ s[:id], Status.new(id: s[:id], name: s[:name], category: CATEGORIES[s[:category]]) ]
        end
      end

      def type_statuses(scope_id)
        statuses_of(scope_id).to_h { |t| [ t[:issue_type], t[:statuses].pluck(:name) ] }
      end

      def statuses_of(scope_id)
        (@statuses ||= {})[scope_id.to_s] ||= api.statuses(scope_id)
      end

      # [{ status: Status, status_ids: [...] }] of the project's first board. A
      # column is done when every status in it is, to-do when every one is, and
      # in progress otherwise.
      def board_columns(scope_id, states)
        board = api.boards(scope_id).first
        return [] unless board

        api.board_columns(board[:id]).filter_map do |column|
          next if column[:status_ids].empty?

          categories = column[:status_ids].filter_map { |id| states[id]&.category }.uniq
          category = categories.one? ? categories.first : "in_progress"
          { status: Status.new(id: column[:name], name: column[:name], category: category), status_ids: column[:status_ids] }
        end
      rescue ::Jira::Error => e
        Rails.logger.info("[Trackers::Jira] board columns unavailable for #{scope_id}: #{e.code}")
        []
      end

      # status id => column name, cached like the status categories.
      def column_index(scope_id)
        Rails.cache.fetch([ "trackers", integration.id, scope_id.to_s, "jira_columns" ], expires_in: 10.minutes) do
          board_columns(scope_id, project_statuses(scope_id)).each_with_object({}) do |column, index|
            column[:status_ids].each { |id| index[id] ||= column[:status].name }
          end
        end
      rescue ::Jira::Error
        {}
      end

      def pick_transition(scope_id, available, status)
        by_status = available.find { |t| t.dig(:to, :name).to_s.casecmp?(status) }
        by_name = available.find { |t| t[:name].to_s.casecmp?(status) }
        return by_status || by_name if by_status || by_name

        column_status_ids = column_index(scope_id).select { |_id, column| column.casecmp?(status) }.keys
        available.find { |t| column_status_ids.include?(t.dig(:to, :id)) }
      end

      # Jira addresses people by account id. A name or an email is looked up
      # among the project's assignable users and must match exactly one.
      def account_id!(scope_id, who)
        value = who.to_s.strip
        return value if value.match?(ACCOUNT_ID)

        candidates = api.assignable_users(project_key: project_key(scope_id), query: value)
        exact = candidates.select { |u| u[:name].to_s.casecmp?(value) || u[:email].to_s.casecmp?(value) }
        match = exact.one? ? exact.first : (candidates.one? ? candidates.first : nil)
        return match[:id] if match

        names = candidates.pluck(:name).first(10)
        raise Error.new("'#{who}' does not name one assignable user#{names.any? ? " — did you mean: #{names.join(', ')}" : ''}",
                        code: "validation_failed", details: { candidates: names })
      end

      def extra_fields(fields)
        extra = fields.to_h.transform_keys(&:to_s).slice(*FIELD_KEYS)
        {
          priority: extra["priority"].presence && { name: extra["priority"].to_s },
          duedate: extra["due_date"].presence,
          parent: extra["parent"].presence && { key: extra["parent"].to_s },
          components: extra["components"].presence && Array(extra["components"]).map { |name| { name: name.to_s } }
        }.compact
      end

      def jql_for(scope_id, filter)
        raise Error.new("This tracker's Jira project id is not numeric", code: "not_configured") unless scope_id.to_s.match?(/\A\d+\z/)

        clauses = [ "project = #{scope_id}" ]
        clauses << "issuekey IN (#{Array(filter[:ids]).map { |id| quote(id) }.join(', ')})" if filter[:ids].present?
        clauses << "issuetype = #{quote(filter[:type])}" if filter[:type].present?
        clauses << status_clause(scope_id, filter[:status]) if filter[:status].present?
        clauses << "assignee = #{quote(account_id!(scope_id, filter[:assignee]))}" if filter[:assignee].present?
        clauses << "summary ~ #{quote(filter[:text])}" if filter[:text].present?
        Array(filter[:labels]).each { |label| clauses << "labels = #{quote(label)}" }
        clauses << "statusCategory != Done" if filter[:open_only]

        condition, order = native_parts(filter[:native_query])
        clauses << "(#{condition})" if condition.present?
        [ clauses.join(" AND "), order.presence || "updated DESC" ]
      end

      def status_clause(scope_id, name)
        ids = column_index(scope_id).select { |_id, column| column.casecmp?(name.to_s) }.keys
        ids.any? ? "status IN (#{ids.join(', ')})" : "status = #{quote(name)}"
      end

      def native_parts(jql)
        return [ nil, nil ] if jql.blank?

        match = jql.to_s.strip.match(/\A(?<condition>.*?)(?:\s*\bORDER\s+BY\s+(?<order>.+))?\z/im)
        [ match[:condition].strip, match[:order]&.strip ]
      end

      def quote(value)
        "\"#{value.to_s.gsub(/["\\]/) { |c| "\\#{c}" }}\""
      end
    end
  end
end
