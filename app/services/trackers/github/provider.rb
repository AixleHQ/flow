# frozen_string_literal: true

module Trackers
  module Github
    # GitHub Projects (v2) as a tracker, over the connection's GitHub App
    # installation. A connection covers the organization projects picked on the
    # Integrations page (`settings.github_projects`); each is a scope, keyed by
    # the project's node id. The status is the project's single-select Status
    # field, which is what the board's columns show.
    #
    # An issue is an issue or pull request on the board, keyed by its node id,
    # with owner/repo#number as its readable key. Draft issues are left out:
    # they have no repository, number or comments.
    class Provider < Trackers::Provider
      DEFAULT_STATUS_FIELD = "Status"
      # A status option carries no category on GitHub, so its name decides; the
      # first match wins.
      CATEGORIES = [
        [ /cancel|won'?t|not planned|duplicate|reject|abandon/i, "canceled" ],
        [ /\bdone\b|closed|complete|shipped|released|merged|resolved/i, "done" ],
        [ /progress|doing|review|test|\bqa\b|blocked|active|started|\bwip\b|develop/i, "in_progress" ]
      ].freeze
      ISSUE_URL = %r{\Ahttps://github\.com/(?<owner>[\w.-]+)/(?<repo>[\w.-]+)/(?:issues|pull)/(?<number>\d+)}i
      ISSUE_KEY = %r{\A(?<owner>[\w.-]+)/(?<repo>[\w.-]+)#(?<number>\d+)\z}
      NODE_ID = /\A(?:I|PR)_[A-Za-z0-9_-]+\z/
      LOGIN = /\A[a-z\d](?:[a-z\d-]{0,38})\z/i
      UNASSIGNED = %w[none unassigned nobody].freeze
      FIELD_KEYS = %w[repository state].freeze
      ISSUE_TYPE = "Issue"

      def serves_project?(project)
        integration.project_id == project.id
      end

      def scopes
        github_projects.map { |p| Scope.new(id: p["id"], key: nil, name: p["title"].presence || "Project #{p['number']}") }
      end

      def covers_scope?(scope_id)
        github_projects.any? { |p| p["id"] == scope_id.to_s }
      end

      # Node ids are unique across GitHub.
      def instance = "github.com"

      # Everything the connection writes is written as the App's bot account.
      def identity
        slug = app_slug
        { "name" => "#{slug}[bot]" } if slug && integration.github_app?
      end

      # People mention the App by its slug; GitHub shows its account as slug[bot].
      def mentions_self?(text)
        slug = app_slug
        slug.present? && text.to_s.match?(/(?<![\w-])@#{Regexp.escape(slug)}(?:\[bot\])?(?![\w-])/i)
      end

      def owns_reference?(_scope_id, ref)
        match = ISSUE_URL.match(ref.to_s.strip) || ISSUE_KEY.match(ref.to_s.strip)
        match.present? && match[:owner].casecmp?(owner_login.to_s)
      end

      def issue_identifier(ref)
        value = ref.to_s.strip
        return value if value.match?(NODE_ID)

        match = ISSUE_URL.match(value) || ISSUE_KEY.match(value)
        "#{match[:owner]}/#{match[:repo]}##{match[:number]}" if match
      end

      # The App delivers its events to /webhooks/github whatever is subscribed;
      # the row only holds the deliveries and when the last one came.
      def ensure_event_delivery!
        subscription
      end

      def subscription
        integration.tracker_subscriptions.find_or_create_by!(external_scope_id: nil) do |subscription|
          subscription.strategy = "app"
          subscription.status = "active"
        end
      end

      def parse_event(event, payload)
        Notifications.parse(event, payload, projects: github_projects)
      end

      def describe(scope_id)
        {
          statuses: status_field!(scope_id)[:options].map { |o| Status.new(id: o[:id], name: o[:name], category: category_for(o[:name])) },
          issue_types: issue_types.map { |name| { name: name } },
          fields: FIELD_KEYS,
          supports: { labels: true, multiple_assignees: true, native_query: true }
        }
      end

      def status_category(_scope_id, name)
        category_for(name) if name.present?
      end

      # Older deliveries name no option, so the issue's column stands in for `to`.
      def status_change(changes, issue)
        change = changes.find { |c| c[:field] == "status" }
        return unless change

        to = change[:to].presence || issue.status&.name
        return if to.blank? || to == change[:from]

        { "field" => "status", "from" => status_value(issue.scope_id, change[:from]),
          "to" => status_value(issue.scope_id, to) }.compact
      end

      def get_issue(scope_id, ref)
        issue_from(placed!(fetch(scope_id, ref), scope_id), scope_id)
      end

      # A native query is GitHub's project filter syntax. It filters this
      # project's items and nothing else, so it cannot reach past the board.
      def search_issues(scope_id, filter, cursor: nil, limit: nil)
        return Page.new(items: by_ids(scope_id, filter[:ids]), next_cursor: nil) if filter[:ids].present?

        result = api.items(scope_id, query: query_for(scope_id, filter), field: status_field_name(scope_id),
                                     limit: (limit || 50).to_i.clamp(1, 100), cursor: cursor)
        Page.new(items: result[:items].map { |content| issue_from(content.merge(placement: content[:placements].first), scope_id) },
                 next_cursor: result[:next_cursor])
      end

      # The issue goes to `fields.repository`, or to the one repository of this
      # organization the Aixle project has, and onto the board.
      def create_issue(scope_id, attributes)
        type = issue_type!(attributes[:type])
        repository = repository_for!(attributes[:fields])
        created = api.create_issue(repository, title: attributes[:title].to_s, body: attributes[:description].presence,
                                               assignees: logins(attributes[:assignee]), labels: Array(attributes[:labels]),
                                               type: type == ISSUE_TYPE ? nil : type)
        begin
          api.add_to_project(scope_id, created[:node_id])
        rescue Error => e
          raise Error::OutcomeUnknown, "Created #{created[:key]}, but it was not added to the project (#{e.message}). " \
                                       "Add it with its URL instead of creating it again"
        end
        get_issue(scope_id, created[:node_id])
      end

      def update_issue(scope_id, ref, attributes)
        if attributes[:expected_revision].present?
          raise Error.new("GitHub issues have no revision to compare; leave expected_revision out", code: "validation_failed")
        end

        content = placed!(fetch(scope_id, ref), scope_id)
        repository, number = content.values_at(:repository, :number)
        changes = { title: attributes[:title], body: attributes[:description], state: state!(attributes[:fields]) }.compact
        adds = Array(attributes[:labels_add])
        removes = Array(attributes[:labels_remove])
        raise Error.new("No fields to update", code: "validation_failed") if changes.empty? && !attributes.key?(:labels) && adds.empty? && removes.empty?

        api.update_issue(repository, number, changes) if changes.any?
        api.set_labels(repository, number, Array(attributes[:labels])) if attributes.key?(:labels)
        api.add_labels(repository, number, adds) if adds.any?
        removes.each { |label| api.remove_label(repository, number, label) }
        get_issue(scope_id, content[:id])
      end

      # `status` is a column of the board: a Status option, by name or id.
      def transition_issue(scope_id, ref, status)
        content = placed!(fetch(scope_id, ref), scope_id)
        return issue_from(content, scope_id) if content.dig(:placement, :status).to_s.casecmp?(status.to_s.strip)

        field = status_field!(scope_id)
        option = field[:options].find { |o| o[:name].casecmp?(status.to_s.strip) || o[:id] == status.to_s }
        unless option
          names = field[:options].pluck(:name)
          raise Error.new("'#{status}' is not a column of this project — columns: #{names.join(', ')}",
                          code: "validation_failed", details: { allowed: names })
        end

        api.set_status(project_id: scope_id, item_id: content.dig(:placement, :item_id), field_id: field[:id], option_id: option[:id])
        get_issue(scope_id, content[:id])
      end

      def assign_issue(scope_id, ref, assignee)
        content = placed!(fetch(scope_id, ref), scope_id)
        wanted = logins(assignee)
        api.update_issue(content[:repository], content[:number], { assignees: wanted })
        issue = get_issue(scope_id, content[:id])
        if wanted.any? && issue.assignees.none? { |login| login.casecmp?(wanted.first) }
          raise Error.new("GitHub did not assign #{wanted.first}: only people with access to #{content[:repository]} can be assigned",
                          code: "validation_failed")
        end

        issue
      end

      def list_users(_scope_id, query:)
        raise Error.new("GitHub assigns by login; pass the person's GitHub login", code: "unsupported")
      end

      def list_comments(scope_id, ref, cursor: nil, limit: nil)
        content = placed!(fetch(scope_id, ref), scope_id)
        result = api.comments(content[:id], limit: (limit || 50).to_i.clamp(1, 100), cursor: cursor)
        Page.new(items: result[:comments].map { |c| comment(c, content[:id]) }, next_cursor: result[:next_cursor])
      end

      def add_comment(scope_id, ref, body)
        content = placed!(fetch(scope_id, ref), scope_id)
        comment(api.add_comment(content[:id], body), content[:id])
      end

      private

      def api
        @api ||= ::Github::ProjectsApi.for(integration)
      end

      def github_projects
        Array(integration.settings.to_h["github_projects"]).select { |p| p.is_a?(Hash) && p["id"].present? }
      end

      def project_entry(scope_id)
        github_projects.find { |p| p["id"] == scope_id.to_s }
      end

      def status_field_name(scope_id)
        project_entry(scope_id)&.dig("status_field").presence || DEFAULT_STATUS_FIELD
      end

      def status_field!(scope_id)
        (@fields ||= {})[scope_id.to_s] ||= begin
          name = status_field_name(scope_id)
          api.project(scope_id, field: name)[:field] ||
            raise(Error.new("This GitHub project has no single-select field named #{name}", code: "not_configured"))
        end
      end

      def owner_login
        integration.github_account_login
      end

      def app_slug
        Settings.github&.app_slug.presence
      end

      def category_for(name)
        CATEGORIES.find { |pattern, _| name.to_s.match?(pattern) }&.last || "todo"
      end

      # "Issue" is a plain issue; anything else is one of the organization's issue types.
      def issue_types
        @issue_types ||= [ ISSUE_TYPE, *api.issue_types(owner_login).pluck(:name) ].uniq
      rescue Error
        @issue_types = [ ISSUE_TYPE ]
      end

      def issue_type!(type)
        return ISSUE_TYPE if type.blank?

        issue_types.find { |name| name.casecmp?(type.to_s.strip) } ||
          raise(Error.new("'#{type}' is not an issue type here — use one of: #{issue_types.join(', ')}", code: "validation_failed"))
      end

      def fetch(scope_id, ref)
        value = ref.to_s.strip
        field = status_field_name(scope_id)
        match = ISSUE_URL.match(value) || ISSUE_KEY.match(value)
        content = if value.match?(NODE_ID)
          api.content(value, field: field)
        elsif match
          api.content_by_number(owner: match[:owner], repo: match[:repo], number: match[:number], field: field)
        else
          raise Error.new("'#{ref}' is not a GitHub issue URL, owner/repo#number or node id", code: "validation_failed")
        end
        content || raise(Error.new("GitHub has no issue #{ref}, or this connection cannot see it", code: "not_found"))
      end

      # The board is the scope: an issue that is not on it is not this tracker's.
      def placed!(content, scope_id)
        placement = content[:placements].find { |p| p[:project_id] == scope_id.to_s }
        return content.merge(placement: placement) if placement

        raise Error.new("#{content[:key]} is not on this tracker's GitHub project", code: "not_found")
      end

      def by_ids(scope_id, ids)
        Array(ids).first(100).filter_map do |id|
          get_issue(scope_id, id)
        rescue Error => e
          raise unless e.code == "not_found"
        end
      end

      def issue_from(content, scope_id)
        status = content.dig(:placement, :status)
        Issue.new(
          id: content[:id], key: content[:key], url: content[:url], title: content[:title], description: content[:body],
          type: content[:type],
          status: status && Status.new(id: content.dig(:placement, :option_id), name: status, category: category_for(status)),
          assignees: content[:assignees], labels: content[:labels], revision: nil, scope_id: scope_id.to_s,
          updated_at: content[:updated_at],
          fields: {
            "repository" => content[:repository], "state" => content[:state]&.downcase,
            "state_reason" => content[:state_reason]&.downcase, "item_id" => content.dig(:placement, :item_id)
          }.compact
        )
      end

      def comment(raw, issue_id)
        Comment.new(id: raw[:id], issue_id: issue_id, author: raw[:author], body: raw[:body], created_at: raw[:created_at])
      end

      def query_for(scope_id, filter)
        parts = [ "-is:draft" ]
        parts << "#{status_field_name(scope_id).downcase.tr(' ', '-')}:#{quote(filter[:status])}" if filter[:status].present?
        parts << type_qualifier(filter[:type]) if filter[:type].present?
        parts << "assignee:#{logins(filter[:assignee]).first || 'none'}" if filter[:assignee].present?
        Array(filter[:labels]).each { |label| parts << "label:#{quote(label)}" }
        parts << "is:open" if filter[:open_only]
        parts << filter[:text].to_s.tr('"', " ").squish if filter[:text].present?
        parts << filter[:native_query].to_s.squish if filter[:native_query].present?
        parts.join(" ")
      end

      def type_qualifier(type)
        return "is:pr" if type.to_s.casecmp?("Pull request")
        return "is:issue" if type.to_s.casecmp?(ISSUE_TYPE)

        "type:#{quote(type)}"
      end

      def quote(value)
        text = value.to_s.tr('"', "")
        text.match?(/[\s,:]/) ? "\"#{text}\"" : text
      end

      def logins(who)
        value = who.to_s.strip.delete_prefix("@")
        return [] if value.blank? || UNASSIGNED.include?(value.downcase)
        raise Error.new("'#{who}' is not a GitHub login", code: "validation_failed") unless value.match?(LOGIN)

        [ value ]
      end

      def state!(fields)
        state = fields.to_h.transform_keys(&:to_s)["state"].to_s.strip.downcase.presence
        return if state.nil?
        return state if %w[open closed].include?(state)

        raise Error.new("fields.state is open or closed", code: "validation_failed")
      end

      def repository_for!(fields)
        named = fields.to_h.transform_keys(&:to_s)["repository"].to_s.strip.presence
        candidates = Repository.for_integration(integration).where(scope_type: "Project", scope_id: integration.project_id)
                               .order(:full_name).pluck(:full_name)
        if named
          owner = named.split("/").first.to_s
          return named if owner.casecmp?(owner_login.to_s) && named.match?(%r{\A[\w.-]+/[\w.-]+\z})

          raise Error.new("'#{named}' is not a repository of #{owner_login}", code: "validation_failed")
        end
        return candidates.first if candidates.one?

        listed = candidates.first(10).join(", ")
        raise Error.new("Name the repository in fields.repository#{listed.present? ? " — one of: #{listed}" : ''}",
                        code: "validation_failed", details: { repositories: candidates.first(10) })
      end
    end
  end
end
