# frozen_string_literal: true

module Trackers
  module Youtrack
    # YouTrack as a tracker. A connection covers the YouTrack projects picked
    # when it was made (`settings.youtrack_projects`); each is a scope, keyed by
    # the project's database id, which survives a short-name change. The status
    # is the project's state field (State unless the project renamed it) — what
    # YouTrack's agile boards are usually built on.
    #
    # Events come from the Aixle Flow app with the subscription's own secret,
    # and still nothing in one is believed: #confirm reads the change, the
    # comment and who made it back from YouTrack (§6.2).
    class Provider < Trackers::Provider
      CANCELED = /cancel|won'?t|duplicate|obsolete|incomplete|can'?t reproduce|reject|invalid|not a bug/i
      IN_PROGRESS = /progress|review|develop|test|\bqa\b|verif|doing|\bwip\b|started|active|blocked/i
      ISSUE_KEY = /\A(?<project>[A-Za-z][A-Za-z0-9_]*)-\d+\z/
      DATABASE_ID = /\A\d+-\d+\z/
      UNASSIGNED = %w[none unassigned nobody].freeze
      TYPE_FIELD = "Type"
      # What the field types YouTrack reports are written as on an issue, for
      # the ones an agent may set by value.
      ISSUE_FIELD_TYPES = {
        "state[1]" => "StateIssueCustomField", "enum[1]" => "SingleEnumIssueCustomField",
        "enum[*]" => "MultiEnumIssueCustomField", "user[1]" => "SingleUserIssueCustomField",
        "user[*]" => "MultiUserIssueCustomField", "ownedField[1]" => "SingleOwnedIssueCustomField",
        "ownedField[*]" => "MultiOwnedIssueCustomField", "version[1]" => "SingleVersionIssueCustomField",
        "version[*]" => "MultiVersionIssueCustomField", "build[1]" => "SingleBuildIssueCustomField",
        "build[*]" => "MultiBuildIssueCustomField", "string" => "SimpleIssueCustomField",
        "integer" => "SimpleIssueCustomField", "float" => "SimpleIssueCustomField", "text" => "TextIssueCustomField"
      }.freeze
      # A webhook may claim an issue was created or commented on; one older than
      # this is a replay, not news.
      FRESH = 1.day
      # The app stamps a comment with its own creation time, so it matches the
      # stored one; the slack only absorbs rounding.
      COMMENT_SKEW = 2.seconds

      def serves_project?(project)
        integration.project_id == project.id
      end

      def scopes
        youtrack_projects.map { |p| Scope.new(id: p["id"].to_s, key: p["key"], name: p["name"].presence || p["key"]) }
      end

      def covers_scope?(scope_id)
        youtrack_projects.any? { |p| p["id"].to_s == scope_id.to_s }
      end

      def instance
        settings["base_url"].to_s
      end

      def own_actor?(actor)
        me = identity
        return false if me.blank? || actor.blank?

        (actor[:id].present? && actor[:id].to_s == me["id"].to_s) ||
          (actor[:login].present? && actor[:login].to_s.casecmp?(me["login"].to_s))
      end

      # YouTrack writes a mention as @login.
      def mentions_self?(text)
        login = identity&.dig("login")
        return false if login.blank? || text.blank?

        text.match?(/(?<![\w.-])@#{Regexp.escape(login)}(?![\w-])/i)
      end

      def owns_reference?(scope_id, ref)
        key = key_in(ref.to_s.strip)
        key.present? && key.split("-").first.casecmp?(project(scope_id)&.dig("key").to_s)
      end

      def issue_identifier(ref)
        issue_ref!(ref)
      rescue Error
        nil
      end

      def ensure_event_delivery!
        Subscriptions.new(integration).ensure!
      end

      def authentic_delivery?(request, _raw_body, subscription)
        Webhooks.authentic?(request, subscription)
      end

      # A subscription belongs to one YouTrack project, whose token it holds.
      def parse_delivery(payload, subscription)
        Notifications.parse(payload, project: project(subscription.external_scope_id))
      end

      # The app sends no delivery id; `at` is when the change happened, so a
      # resend digests the same.
      def delivery_id(_request, payload)
        Digest::SHA256.hexdigest(payload.to_json)
      end

      def confirm(notification, issue)
        case notification.kind
        when :issue_created then confirm_created(notification, issue)
        when :comment_created then confirm_comment(notification, issue)
        when :issue_updated then confirm_changes(notification, issue)
        end
      end

      def describe(scope_id)
        fields = project_fields(scope_id)
        status = status_field(scope_id, fields)
        types = fields.find { |f| f[:name] == TYPE_FIELD }
        assignee = assignee_field(scope_id, fields)
        {
          statuses: Array(status&.dig(:values)).map { |v| Status.new(id: v[:id], name: v[:name], category: category(v[:name], v[:resolved])) },
          issue_types: Array(types&.dig(:values)).map { |v| { name: v[:name] } },
          fields: editable(fields, scope_id).map { |f| f[:name] },
          supports: { labels: true, multiple_assignees: assignee&.dig(:field_type) == "user[*]", native_query: true }
        }
      end

      def get_issue(scope_id, ref)
        issue_from(scoped!(fetch(issue_ref!(ref)), scope_id), scope_id)
      end

      # `native_query` is YouTrack's query language, ANDed after the project;
      # whatever it says, an issue outside the project is dropped.
      def search_issues(scope_id, filter, cursor: nil, limit: nil)
        return Page.new(items: by_ids(scope_id, filter[:ids]), next_cursor: nil) if filter[:ids].present?

        top = (limit || 50).to_i.clamp(1, 100)
        skip = cursor.to_i.clamp(0, 10_000)
        raw = api.issues(query: query_for(scope_id, filter), top: top, skip: skip)
        items = raw.select { |issue| issue[:project_id] == scope_id.to_s }.map { |issue| issue_from(issue, scope_id) }
        Page.new(items: items, next_cursor: raw.size == top ? (skip + top).to_s : nil)
      end

      def create_issue(scope_id, attributes)
        fields = project_fields(scope_id)
        custom = []
        custom << field_value(fields, TYPE_FIELD, attributes[:type]) if attributes[:type].present?
        if attributes[:assignee].present?
          custom << user_value(assignee_field!(scope_id, fields), user_login!(scope_id, attributes[:assignee]))
        end
        custom.concat(extra_fields(scope_id, fields, attributes[:fields]))
        body = { project: { id: scope_id.to_s }, summary: attributes[:title].to_s, description: attributes[:description].presence,
                 customFields: custom.presence, tags: attributes[:labels].present? ? tag_refs!(attributes[:labels]) : nil }.compact
        issue_from(scoped!(api.create_issue(body), scope_id), scope_id)
      end

      def update_issue(scope_id, ref, attributes)
        if attributes[:expected_revision].present?
          raise Error.new("YouTrack issues have no revision to compare; leave expected_revision out", code: "validation_failed")
        end

        current = scoped!(fetch(issue_ref!(ref)), scope_id)
        body = { summary: attributes[:title], description: attributes[:description] }.compact
        custom = extra_fields(scope_id, project_fields(scope_id), attributes[:fields])
        body[:customFields] = custom if custom.any?
        add, remove = tag_changes(current, attributes)
        raise Error.new("No fields to update", code: "validation_failed") if body.empty? && add.empty? && remove.empty?

        api.update_issue(current[:id], body) if body.any?
        add.each { |tag| api.add_tag(current[:id], tag[:id]) }
        remove.each { |tag| api.remove_tag(current[:id], tag[:id]) }
        issue_from(fetch(current[:id], fresh: true), scope_id)
      end

      # `status` is a value of the project's state field, by name or id. A
      # transition YouTrack's workflow rules forbid comes back refused.
      def transition_issue(scope_id, ref, status)
        current = scoped!(fetch(issue_ref!(ref)), scope_id)
        field = status_field!(scope_id)
        return issue_from(current, scope_id) if field_name_of(current, field[:name]).to_s.casecmp?(status.to_s.strip)

        target = field[:values].find { |v| v[:name].casecmp?(status.to_s.strip) || v[:id] == status.to_s }
        unless target
          names = field[:values].pluck(:name)
          raise Error.new("'#{status}' is not a #{field[:name]} of this project — values: #{names.join(', ')}",
                          code: "validation_failed", details: { allowed: names })
        end

        value = { name: field[:name], "$type": ISSUE_FIELD_TYPES.fetch(field[:field_type], "StateIssueCustomField"),
                  value: { name: target[:name] } }
        issue_from(api.update_issue(current[:id], { customFields: [ value ] }), scope_id)
      end

      def assign_issue(scope_id, ref, assignee)
        current = scoped!(fetch(issue_ref!(ref)), scope_id)
        field = assignee_field!(scope_id, project_fields(scope_id))
        unassign = assignee.blank? || UNASSIGNED.include?(assignee.to_s.downcase)
        value = user_value(field, unassign ? nil : user_login!(scope_id, assignee))
        issue_from(api.update_issue(current[:id], { customFields: [ value ] }), scope_id)
      end

      def list_users(scope_id, query:)
        users = assignable(scope_id)
        users = users.select { |u| [ u[:login], u[:name], u[:email] ].compact.any? { |v| v.downcase.include?(query.to_s.downcase) } } if query.present?
        users.first(100).map { |u| { id: u[:login], name: u[:name] } }
      end

      def list_comments(scope_id, ref, cursor: nil, limit: nil)
        current = scoped!(fetch(issue_ref!(ref)), scope_id)
        top = (limit || 50).to_i.clamp(1, 100)
        skip = cursor.to_i.clamp(0, 10_000)
        comments = api.comments(current[:id], top: top, skip: skip)
        Page.new(items: comments.map { |c| comment(c, current[:id]) }, next_cursor: comments.size == top ? (skip + top).to_s : nil)
      end

      def add_comment(scope_id, ref, body)
        current = scoped!(fetch(issue_ref!(ref)), scope_id)
        comment(api.add_comment(current[:id], body), current[:id])
      end

      private

      def api
        @api ||= ::Youtrack::Api.for(integration)
      end

      def settings
        integration.settings.to_h
      end

      def youtrack_projects
        Array(settings["youtrack_projects"]).select { |p| p.is_a?(Hash) && p["id"].present? }
      end

      def project(scope_id)
        youtrack_projects.find { |p| p["id"].to_s == scope_id.to_s }
      end

      # The pipeline reads an issue and then confirms against it; one read serves both.
      def fetch(ref, fresh: false)
        @issues ||= {}
        return @issues[ref.to_s] if !fresh && @issues.key?(ref.to_s)

        raw = api.issue(ref)
        [ ref, raw&.dig(:id), raw&.dig(:key) ].compact_blank.each { |k| @issues[k.to_s] = raw }
        raw
      end

      def project_fields(scope_id)
        Rails.cache.fetch([ "trackers", integration.id, scope_id.to_s, "youtrack_fields" ], expires_in: 10.minutes) do
          api.project_fields(scope_id)
        end
      end

      def status_field(scope_id, fields = project_fields(scope_id))
        name = project(scope_id)&.dig("status_field")
        fields.find { |f| f[:name] == name } || fields.find { |f| f[:field_type].start_with?("state") }
      end

      def status_field!(scope_id)
        status_field(scope_id) || raise(Error.new("This YouTrack project has no state field", code: "not_configured"))
      end

      def assignee_field(scope_id, fields)
        name = project(scope_id)&.dig("assignee_field").presence || "Assignee"
        users = fields.select { |f| f[:field_type].start_with?("user") }
        users.find { |f| f[:name] == name } || users.first
      end

      def assignee_field!(scope_id, fields)
        assignee_field(scope_id, fields) || raise(Error.new("This YouTrack project has no assignee field", code: "not_configured"))
      end

      def assignable(scope_id)
        assignee_field(scope_id, project_fields(scope_id))&.dig(:users) || []
      end

      # The fields an agent may set through `fields`: the ones whose values can be
      # written by name, except those the other arguments set.
      def editable(fields, scope_id)
        taken = [ status_field(scope_id, fields)&.dig(:name), assignee_field(scope_id, fields)&.dig(:name), TYPE_FIELD ].compact
        fields.select { |f| ISSUE_FIELD_TYPES.key?(f[:field_type]) && taken.exclude?(f[:name]) }
      end

      def category(name, resolved)
        if resolved then name.to_s.match?(CANCELED) ? "canceled" : "done"
        elsif name.to_s.match?(IN_PROGRESS) then "in_progress"
        else "todo"
        end
      end

      def scoped!(raw, scope_id)
        raise Error.new("YouTrack has no such issue, or this connection cannot see it", code: "not_found") if raw.nil?
        return remember_key(raw, scope_id) if raw[:project_id] == scope_id.to_s

        raise Error.new("#{raw[:key].presence || raw[:id]} is not in this tracker's YouTrack project", code: "not_found")
      end

      # A project renamed in YouTrack keeps its id and changes its short name,
      # which queries and issue keys use: the one an issue comes back with wins.
      def remember_key(raw, scope_id)
        key = raw[:project_key].to_s
        return raw if key.blank? || key == project(scope_id)&.dig("key")

        projects = youtrack_projects.map { |p| p["id"].to_s == scope_id.to_s ? p.merge("key" => key) : p }
        integration.update_columns(settings: settings.merge("youtrack_projects" => projects), updated_at: Time.current)
        integration.project_trackers.where(external_scope_id: scope_id.to_s).update_all(external_scope_key: key)
        raw
      end

      def issue_ref!(ref)
        value = ref.to_s.strip
        key = key_in(value)
        return key if key
        return value if value.match?(DATABASE_ID)

        raise Error.new("'#{ref}' is not a YouTrack issue id or URL", code: "validation_failed")
      end

      # A browser URL of this instance (…/issue/APP-12/slug), or a readable id.
      def key_in(value)
        if value.match?(%r{\Ahttps?://}i)
          uri = URI.parse(value)
          base = URI.parse(instance)
          return unless uri.host.to_s.casecmp?(base.host.to_s) && uri.path.start_with?(base.path.to_s)

          candidate = uri.path[%r{/issue/([^/?#]+)}, 1]
          return candidate.upcase if candidate.to_s.match?(ISSUE_KEY)

          return
        end
        value.upcase if value.match?(ISSUE_KEY)
      rescue URI::InvalidURIError
        nil
      end

      def by_ids(scope_id, ids)
        Array(ids).first(100).filter_map do |id|
          get_issue(scope_id, id)
        rescue Error => e
          raise unless e.code == "not_found"
        end
      end

      def issue_from(raw, scope_id)
        state = field_value_of(raw, status_field(scope_id)&.dig(:name))
        assignee = field_value_of(raw, assignee_field(scope_id, project_fields(scope_id))&.dig(:name))
        Issue.new(
          id: raw[:id], key: raw[:key], url: browse_url(raw[:key]), title: raw[:title], description: raw[:description],
          type: field_name_of(raw, TYPE_FIELD),
          status: state.is_a?(Hash) && state[:name].present? ? Status.new(id: state[:id], name: state[:name], category: category(state[:name], state[:resolved])) : nil,
          assignees: Array(assignee.is_a?(Array) ? assignee : [ assignee ]).filter_map { |u| u.is_a?(Hash) ? u[:login] : nil },
          labels: raw[:tags].pluck(:name), revision: nil, scope_id: scope_id.to_s, updated_at: raw[:updated_at],
          fields: extra_values(raw, scope_id)
        )
      end

      def extra_values(raw, scope_id)
        names = editable(project_fields(scope_id), scope_id).map { |f| f[:name] }
        raw[:custom_fields].select { |f| names.include?(f[:name]) }.to_h { |f| [ f[:name], display(f[:value]) ] }.compact
      end

      def display(value)
        case value
        when Array then value.map { |v| display(v) }.compact.presence
        when Hash then value[:login] || value[:name] || value[:text]
        else value
        end
      end

      def field_value_of(raw, name)
        raw[:custom_fields].find { |f| f[:name] == name }&.dig(:value) if name
      end

      def field_name_of(raw, name)
        value = field_value_of(raw, name)
        value[:name] if value.is_a?(Hash)
      end

      def browse_url(key)
        "#{instance}/issue/#{key}" if instance.present? && key.present?
      end

      def comment(raw, issue_id)
        Comment.new(id: raw[:id], issue_id: issue_id, author: raw.dig(:author, :login), body: raw[:text], created_at: raw[:created_at])
      end

      def query_for(scope_id, filter)
        clauses = [ "project: #{braced(project(scope_id)&.dig('key') || scope_id)}" ]
        clauses << "#{TYPE_FIELD}: #{braced(filter[:type])}" if filter[:type].present?
        clauses << "#{attribute(status_field!(scope_id)[:name])}: #{braced(filter[:status])}" if filter[:status].present?
        if filter[:assignee].present?
          field = assignee_field!(scope_id, project_fields(scope_id))
          clauses << "#{attribute(field[:name])}: #{user_login!(scope_id, filter[:assignee])}"
        end
        clauses << "\"#{filter[:text].to_s.delete('"')}\"" if filter[:text].present?
        Array(filter[:labels]).each { |label| clauses << "tag: #{braced(label)}" }
        clauses << "#Unresolved" if filter[:open_only]
        clauses << "(#{filter[:native_query].to_s.sub(/\bsort\s+by:.*\z/im, '').strip})" if filter[:native_query].present?
        order = filter[:native_query].to_s[/\bsort\s+by:.*\z/im].presence || "sort by: updated desc"
        "#{clauses.join(' and ')} #{order}"
      end

      def braced(value)
        "{#{value.to_s.delete('{}')}}"
      end

      # A field name with a space is written in braces in a query.
      def attribute(name)
        name.include?(" ") ? braced(name) : name
      end

      # YouTrack addresses people by login. A name or an email is looked up
      # among the people the assignee field offers and must match exactly one.
      def user_login!(scope_id, who)
        value = who.to_s.strip.delete_prefix("@")
        candidates = assignable(scope_id)
        exact = candidates.select { |u| [ u[:login], u[:name], u[:email], u[:id] ].compact.any? { |v| v.casecmp?(value) } }
        partial = candidates.select { |u| [ u[:login], u[:name], u[:email] ].compact.any? { |v| v.downcase.include?(value.downcase) } }
        match = exact.one? ? exact.first : (exact.empty? && partial.one? ? partial.first : nil)
        return match[:login] if match

        names = (exact.presence || partial).map { |u| u[:login] }.first(10)
        raise Error.new("'#{who}' does not name one person this project's issues can be assigned to" \
                        "#{names.any? ? " — did you mean: #{names.join(', ')}" : ''}",
                        code: "validation_failed", details: { candidates: names })
      end

      def user_value(field, login)
        multi = field[:field_type] == "user[*]"
        value = if login.nil? then multi ? [] : nil
        else multi ? [ { login: login } ] : { login: login }
        end
        { name: field[:name], "$type": ISSUE_FIELD_TYPES.fetch(field[:field_type]), value: value }
      end

      # One field set by the value's name, as the project's bundle names it.
      def field_value(fields, name, value)
        field = fields.find { |f| f[:name].casecmp?(name.to_s) }
        raise Error.new("This YouTrack project has no field '#{name}'", code: "validation_failed") unless field

        type = ISSUE_FIELD_TYPES[field[:field_type]]
        raise Error.new("Aixle cannot set the field '#{field[:name]}'", code: "validation_failed") unless type

        { name: field[:name], "$type": type, value: written(field, value) }
      end

      def written(field, value)
        kind, arity = field[:field_type].split("[")
        return { text: value.to_s } if kind == "text"
        return number_or_text(kind, value) if %w[string integer float].include?(kind)

        values = Array(value).map(&:to_s).compact_blank
        values.each { |v| known_value!(field, v) } if field[:values].any?
        refs = values.map { |v| kind == "user" ? { login: v } : { name: v } }
        arity == "*]" ? refs : refs.first
      end

      def number_or_text(kind, value)
        return value.to_s if kind == "string"

        number = kind == "integer" ? Integer(value.to_s, exception: false) : Float(value.to_s, exception: false)
        raise Error.new("'#{value}' is not a#{kind == 'integer' ? 'n integer' : ' number'}", code: "validation_failed") if number.nil?

        number
      end

      def known_value!(field, value)
        return if field[:values].any? { |v| v[:name].casecmp?(value) }

        names = field[:values].pluck(:name)
        raise Error.new("'#{value}' is not a value of #{field[:name]} — values: #{names.first(30).join(', ')}",
                        code: "validation_failed", details: { allowed: names })
      end

      def extra_fields(scope_id, fields, extra)
        allowed = editable(fields, scope_id).map { |f| f[:name].downcase }
        extra.to_h.map do |name, value|
          unless allowed.include?(name.to_s.downcase)
            raise Error.new("'#{name}' is not a field Aixle can set here — tracker_describe lists them", code: "validation_failed")
          end

          field_value(fields, name, value)
        end
      end

      def tag_refs!(names)
        tags_named!(names).map { |tag| { id: tag[:id] } }
      end

      def tags_named!(names)
        wanted = Array(names).map(&:to_s).compact_blank.uniq
        return [] if wanted.empty?

        available = (@tags ||= api.tags)
        unknown = wanted.reject { |name| available.any? { |t| t[:name].casecmp?(name) } }
        if unknown.any?
          raise Error.new("No such tag: #{unknown.join(', ')} — tags: #{available.pluck(:name).first(30).join(', ')}",
                          code: "validation_failed")
        end

        wanted.map { |name| available.find { |t| t[:name].casecmp?(name) } }.uniq
      end

      # [tags to add, tags to remove], from `labels` (the whole set) or
      # `labels_add` / `labels_remove`.
      def tag_changes(current, attributes)
        held = current[:tags]
        if attributes.key?(:labels)
          wanted = tags_named!(attributes[:labels])
          return [ wanted.reject { |t| held.any? { |h| h[:id] == t[:id] } }, held.reject { |h| wanted.any? { |t| t[:id] == h[:id] } } ]
        end

        add = tags_named!(attributes[:labels_add]).reject { |t| held.any? { |h| h[:id] == t[:id] } }
        remove = Array(attributes[:labels_remove]).filter_map { |name| held.find { |h| h[:name].casecmp?(name.to_s) } }
        [ add, remove ]
      end

      def actor(user)
        return {} if user.blank?

        { id: user[:id], login: user[:login], name: user[:name] }.compact
      end

      def fresh?(time)
        time.present? && Time.zone.parse(time.to_s) > FRESH.ago
      end

      def confirm_created(notification, issue)
        raw = fetch(issue.id)
        return unless fresh?(raw[:created_at])

        notification.with(actor: actor(raw[:reporter]), revision: "created")
      end

      def confirm_comment(notification, issue)
        comment = notification.comment_id.present? ? api.comment(issue.id, notification.comment_id) : comment_hinted(notification, issue)
        return if comment.nil? || !fresh?(comment[:created_at])

        notification.with(comment_id: comment[:id], comment_text: comment[:text], actor: actor(comment[:author]))
      rescue Error => e
        raise unless e.code == "not_found"
      end

      # When the app could not read the comment's id: who wrote it and when.
      def comment_hinted(notification, issue)
        login = notification.actor[:login].to_s
        at = notification.occurred_at && Time.zone.parse(notification.occurred_at)
        return if login.blank? || at.nil?

        api.recent_comments(issue.id).find do |c|
          c.dig(:author, :login).to_s.casecmp?(login) && c[:created_at] && (Time.zone.parse(c[:created_at]) - at).abs <= COMMENT_SKEW
        end
      end

      # A change counts when YouTrack's own history has it; the issue's current
      # value alone is enough only when the history has aged out of the page read.
      def confirm_changes(notification, issue)
        fields = { "status" => status_field(issue.scope_id)&.dig(:name),
                   "assignee" => assignee_field(issue.scope_id, project_fields(issue.scope_id))&.dig(:name) }
        activities = api.field_activities(issue.id)
        confirmed = notification.changes.filter_map do |change|
          activity = activities.find do |a|
            a[:field] == fields[change[:field]] && a[:added].any? { |name| name.casecmp?(change[:to].to_s) } && fresh?(a[:at])
          end
          next [ change.merge(from: activity[:removed].first || change[:from]).compact, activity ] if activity
          next [ change, nil ] if current?(issue, change)
        end
        return if confirmed.empty?

        activity = confirmed.filter_map(&:last).first
        notification.with(changes: confirmed.map(&:first), actor: activity ? actor(activity[:author]) : {},
                          revision: activity&.dig(:id) || "#{issue.updated_at}:#{confirmed.map { |c, _| c[:to] }.join(',')}")
      end

      def current?(issue, change)
        case change[:field]
        when "status" then issue.status&.name.to_s.casecmp?(change[:to].to_s)
        when "assignee" then issue.assignees.any? { |login| login.casecmp?(change[:to].to_s) }
        end
      end
    end
  end
end
