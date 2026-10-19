# frozen_string_literal: true

module Trackers
  module Gitlab
    # GitLab issues as a tracker, over the connection's code-host token
    # (docs/design/gitlab-tracker.md §5). A scope is a GitLab project, keyed by
    # its numeric id, with the board picked for it (`settings.gitlab_trackers`).
    #
    # The columns are Open, the board's label lists in board order, and Closed.
    # An issue is in Closed when closed, else in the first list whose label it
    # carries, else in Open; moving it swaps those labels and closes or reopens it.
    #
    # An issue's id is "<project id>:<iid>" — GitLab finds an issue by its global
    # id for administrators only — and its key is GitLab's own `group/project#iid`.
    class Provider < Trackers::Provider
      OPEN = "Open"
      CLOSED = "Closed"
      CATEGORIES = [
        [ /cancel|won'?t|not planned|duplicate|reject|abandon/i, "canceled" ],
        [ /\bdone\b|complete|shipped|released|merged|resolved|verified/i, "done" ],
        [ /progress|doing|review|test|\bqa\b|blocked|active|started|\bwip\b|develop/i, "in_progress" ]
      ].freeze
      ISSUE_ID = /\A(?<project>\d+):(?<iid>\d+)\z/
      ISSUE_KEY = %r{\A(?<path>[\w.\-/]+)#(?<iid>\d+)\z}
      ISSUE_URL = %r{\Ahttps?://[^/]+/(?<path>[\w.\-/]+?)/-/(?:issues|work_items)/(?<iid>\d+)}i
      ISSUE_TYPES = %w[issue incident task].freeze
      UNASSIGNED = %w[none unassigned nobody].freeze
      # An upload linked from an issue's Markdown: `/uploads/<secret>/<name>`,
      # relative, or absolute under a project path or /-/project/<id>/.
      UPLOAD = %r{(!?)\[([^\]]*)\]\(((?:https?://[^\s)]+)?/uploads/(\h{32})/([^)\s]+))\)}
      COMMENT_PAGES = 5

      def serves_project?(project)
        integration.project_id == project.id
      end

      def scopes
        gitlab_trackers.map { |t| Scope.new(id: t["id"].to_s, key: t["path"], name: t["name"].presence || t["path"]) }
      end

      def covers_scope?(scope_id)
        gitlab_trackers.any? { |t| t["id"].to_s == scope_id.to_s }
      end

      def instance
        URI.parse(::Gitlab::Host.web_base).host.to_s
      end

      # A pasted token acts as the person it belongs to; only a service account
      # is Aixle's own identity.
      def identity
        return unless settings["auth_mode"] == ::Gitlab::IntegrationService::SERVICE_ACCOUNT_MODE

        { "id" => settings["gitlab_user_id"].to_s, "name" => settings["gitlab_username"] }.compact_blank.presence
      end

      def owns_reference?(scope_id, ref)
        path = reference_path(ref.to_s)
        path.present? && path.casecmp?(tracker(scope_id)&.dig("path").to_s)
      end

      def issue_identifier(ref)
        ref.to_s.strip if ref.to_s.strip.match?(ISSUE_ID)
      end

      def ensure_event_delivery!
        Subscriptions.new(integration).ensure!
      end

      def authentic_delivery?(request, _raw_body, subscription)
        token = request.headers["X-Gitlab-Token"].to_s
        subscription.secret.present? && token.present? && ActiveSupport::SecurityUtils.secure_compare(token, subscription.secret)
      end

      def parse_delivery(payload, subscription)
        scope_id = subscription.external_scope_id.to_s
        return [] unless covers_scope?(scope_id)

        Notifications.parse(payload, scope_id: scope_id, lists: lists(scope_id))
      end

      def delivery_id(request, _payload)
        request.headers["Idempotency-Key"].presence || request.headers["X-Gitlab-Event-UUID"].presence
      end

      def describe(scope_id)
        {
          statuses: statuses(scope_id),
          issue_types: ISSUE_TYPES.map { |name| { name: name } },
          fields: %w[state],
          supports: { labels: true, multiple_assignees: false, native_query: false }
        }
      end

      def status_category(_scope_id, name)
        return if name.blank?
        return "todo" if name == OPEN
        return "done" if name == CLOSED

        CATEGORIES.find { |pattern, _| name.to_s.match?(pattern) }&.last || "todo"
      end

      def get_issue(scope_id, ref)
        issue_from(fetch(scope_id, ref), scope_id)
      end

      def search_issues(scope_id, filter, cursor: nil, limit: nil)
        per_page = (limit || 50).to_i.clamp(1, 100)
        result = api.issues(scope_id, params: search_params(scope_id, filter), page: [ cursor.to_i, 1 ].max, per_page: per_page)
        issues = result[:issues].select { |raw| raw[:project_id] == scope_id.to_s }
        Page.new(items: issues.map { |raw| issue_from(raw, scope_id) }, next_cursor: result[:next_page]&.to_s)
      end

      def create_issue(scope_id, attributes)
        type = attributes[:type].to_s.downcase.presence || "issue"
        unless ISSUE_TYPES.include?(type)
          raise Error.new("'#{attributes[:type]}' is not an issue type here — use one of: #{ISSUE_TYPES.join(', ')}",
                          code: "validation_failed")
        end

        body = { title: attributes[:title].to_s, description: attributes[:description].presence, issue_type: type,
                 labels: Array(attributes[:labels]).join(",").presence }.compact
        body[:assignee_ids] = [ member_id!(scope_id, attributes[:assignee]) ] if attributes[:assignee].present?
        issue_from(api.create_issue(scope_id, body), scope_id)
      end

      def update_issue(scope_id, ref, attributes)
        if attributes[:expected_revision].present?
          raise Error.new("GitLab issues have no revision to compare; leave expected_revision out", code: "validation_failed")
        end

        current = fetch(scope_id, ref)
        body = { title: attributes[:title], description: attributes[:description], state_event: state_event!(attributes[:fields]) }.compact
        body[:labels] = Array(attributes[:labels]).join(",") if attributes.key?(:labels)
        body[:add_labels] = Array(attributes[:labels_add]).join(",") if attributes[:labels_add].present?
        body[:remove_labels] = Array(attributes[:labels_remove]).join(",") if attributes[:labels_remove].present?
        raise Error.new("No fields to update", code: "validation_failed") if body.empty?

        issue_from(api.update_issue(scope_id, current[:iid], body), scope_id)
      end

      # `status` is a column: Open, Closed or one of the board's label lists.
      def transition_issue(scope_id, ref, status)
        current = fetch(scope_id, ref)
        target = statuses(scope_id).find { |s| s.name.casecmp?(status.to_s.strip) }
        unless target
          names = statuses(scope_id).map(&:name)
          raise Error.new("'#{status}' is not a column of this board — columns: #{names.join(', ')}",
                          code: "validation_failed", details: { allowed: names })
        end
        return issue_from(current, scope_id) if column_of(current, scope_id) == target.name

        others = lists(scope_id) - [ target.name ]
        body = { remove_labels: (current[:labels] & others).join(",").presence }
        if target.name == CLOSED
          body[:state_event] = "close"
        else
          body[:add_labels] = target.name unless target.name == OPEN
          body[:state_event] = "reopen" if current[:state] == "closed"
        end
        issue_from(api.update_issue(scope_id, current[:iid], body.compact), scope_id)
      end

      def assign_issue(scope_id, ref, assignee)
        current = fetch(scope_id, ref)
        ids = assignee.blank? || UNASSIGNED.include?(assignee.to_s.downcase) ? [ 0 ] : [ member_id!(scope_id, assignee) ]
        issue_from(api.update_issue(scope_id, current[:iid], { assignee_ids: ids }), scope_id)
      end

      def list_users(scope_id, query:)
        api.members(scope_id, query: query).map { |m| { id: m[:username], name: m[:name] } }
      end

      def list_comments(scope_id, ref, cursor: nil, limit: nil)
        current = fetch(scope_id, ref)
        result = api.notes(scope_id, current[:iid], page: [ cursor.to_i, 1 ].max, per_page: (limit || 50).to_i.clamp(1, 100))
        Page.new(items: result[:notes].map { |n| comment(n, current[:id]) }, next_cursor: result[:next_page]&.to_s)
      end

      def add_comment(scope_id, ref, body)
        current = fetch(scope_id, ref)
        comment(api.add_note(scope_id, current[:iid], body), current[:id])
      end

      # GitLab keeps no list of an issue's files: they are uploads its
      # description and notes link to. Every file of a confidential issue, and
      # of an internal note, is visible to fewer people than an Aixle project.
      def attachments? = true
      def attachment_list? = false

      def list_attachments(scope_id, ref)
        files_of(fetch(scope_id, ref))
      end

      def download_attachment(scope_id, ref, attachment_id, io:, max_bytes:)
        current = fetch(scope_id, ref)
        found = files_of(current).find { |a| a.id == attachment_id.to_s }
        raise Error.new("#{current[:key]} has no file #{attachment_id}", code: "not_found") unless found
        raise Error.new("#{found.name} is on a confidential issue or an internal note", code: "restricted") if found.restricted

        secret, filename = found.id.split("/", 2)
        fetched = api.download(scope_id, secret, filename, io: io, max_bytes: max_bytes)
        found.with(content_type: fetched[:content_type])
      end

      def upload_attachment(scope_id, ref, file)
        current = fetch(scope_id, ref)
        uploaded = api.upload(scope_id, file)
        @files&.delete(current[:id])
        Attachment.new(id: "#{uploaded[:secret]}/#{uploaded[:filename]}", issue_id: current[:id], name: uploaded[:filename],
                       size: file.size, content_type: file.content_type, origin: :embedded,
                       url: "#{::Gitlab::Host.web_base}/#{tracker(scope_id)&.dig('path')}#{uploaded[:url]}")
      end

      # Relative upload links resolve to the issue's own project.
      def attachment_markup(attachment)
        secret, filename = attachment.id.to_s.split("/", 2)
        target = "/uploads/#{secret}/#{ERB::Util.url_encode(filename)}"
        label = attachment.name.to_s.gsub(/[\[\]]/, "")
        attachment.image? ? "![#{label}](#{target})" : "[#{label}](#{target})"
      end

      private

      def api
        @api ||= ::Gitlab::TrackerApi.for(integration)
      end

      def settings
        integration.settings.to_h
      end

      def gitlab_trackers
        Array(settings["gitlab_trackers"]).select { |t| t.is_a?(Hash) && t["id"].present? }
      end

      def tracker(scope_id)
        gitlab_trackers.find { |t| t["id"].to_s == scope_id.to_s }
      end

      # The board's label lists, in board order, cached like the other providers' metadata.
      def lists(scope_id)
        board_id = tracker(scope_id)&.dig("board_id")
        return [] if board_id.blank?

        Rails.cache.fetch([ "trackers", integration.id, scope_id.to_s, "gitlab_lists", board_id ], expires_in: 10.minutes) do
          api.boards(scope_id).find { |b| b[:id] == board_id.to_s }&.dig(:lists) || []
        end
      end

      def statuses(scope_id)
        [ OPEN, *lists(scope_id), CLOSED ].map { |name| Status.new(id: name, name: name, category: status_category(scope_id, name)) }
      end

      def column_of(raw, scope_id)
        return CLOSED if raw[:state] == "closed"

        lists(scope_id).find { |label| raw[:labels].include?(label) } || OPEN
      end

      # The issue, which must be in the scope's project.
      def fetch(scope_id, ref)
        project_id, iid = locate(scope_id, ref)
        raise Error.new("'#{ref}' is not in this tracker's GitLab project", code: "not_found") unless project_id == scope_id.to_s

        @issues ||= {}
        @issues["#{project_id}:#{iid}"] ||= api.issue(project_id, iid) ||
                                             raise(Error.new("GitLab has no issue #{ref}", code: "not_found"))
      end

      def locate(scope_id, ref)
        value = ref.to_s.strip
        if (m = ISSUE_ID.match(value)) then [ m[:project], m[:iid].to_i ]
        elsif value.match?(/\A#?\d+\z/) then [ scope_id.to_s, value.delete_prefix("#").to_i ]
        elsif reference_path(value)
          raise Error.new("#{value} is not in this tracker's GitLab project", code: "not_found") unless owns_reference?(scope_id, value)

          [ scope_id.to_s, (ISSUE_URL.match(value) || ISSUE_KEY.match(value))[:iid].to_i ]
        else
          raise Error.new("'#{ref}' is not a GitLab issue key (group/project#12), number or URL", code: "validation_failed")
        end
      end

      def reference_path(value)
        if (m = ISSUE_URL.match(value))
          host = URI.parse(value).host.to_s
          m[:path] if host.casecmp?(instance)
        elsif (m = ISSUE_KEY.match(value))
          m[:path]
        end
      rescue URI::InvalidURIError
        nil
      end

      def issue_from(raw, scope_id)
        column = column_of(raw, scope_id)
        Issue.new(
          id: raw[:id], key: raw[:key], url: raw[:url], title: raw[:title], description: raw[:description],
          type: raw[:type], status: Status.new(id: column, name: column, category: status_category(scope_id, column)),
          assignees: raw[:assignees].pluck(:username), labels: raw[:labels] - lists(scope_id), revision: nil,
          scope_id: scope_id.to_s, updated_at: raw[:updated_at],
          fields: { "state" => raw[:state], "confidential" => raw[:confidential] || nil }.compact
        )
      end

      def comment(raw, issue_id)
        Comment.new(id: raw[:id], issue_id: issue_id, author: raw[:author], body: raw[:body], created_at: raw[:created_at])
      end

      def search_params(scope_id, filter)
        params = { order_by: "updated_at", sort: "desc", search: filter[:text].presence, issue_type: filter[:type].presence,
                   assignee_username: filter[:assignee].presence, updated_after: filter[:updated_since].presence }
        labels = Array(filter[:labels])
        case filter[:status].to_s
        when "" then params[:state] = "opened" if filter[:open_only]
        when /\A#{CLOSED}\z/i then params[:state] = "closed"
        when /\A#{OPEN}\z/i
          params[:state] = "opened"
          params[:not] = { labels: lists(scope_id).join(",") } if lists(scope_id).any?
        else
          params[:state] = "opened"
          labels << (lists(scope_id).find { |l| l.casecmp?(filter[:status].to_s) } || filter[:status].to_s)
        end
        params[:labels] = labels.join(",") if labels.any?
        params[:iids] = Array(filter[:ids]).filter_map { |id| ISSUE_ID.match(id.to_s)&.[](:iid) || id.to_s[/\A\d+\z/] } if filter[:ids].present?
        params.compact
      end

      def state_event!(fields)
        state = fields.to_h.transform_keys(&:to_s)["state"].to_s.downcase
        return if state.blank?
        return "close" if state == "closed"
        return "reopen" if state.in?(%w[open opened])

        raise Error.new("fields.state is open or closed", code: "validation_failed")
      end

      def member_id!(scope_id, who)
        value = who.to_s.strip.delete_prefix("@")
        members = api.members(scope_id, query: value)
        match = members.find { |m| m[:username].to_s.casecmp?(value) } ||
                (members.one? ? members.first : nil)
        return match[:id] if match

        raise Error.new("'#{who}' is not a member of this GitLab project — pass their GitLab username",
                        code: "validation_failed", details: { candidates: members.pluck(:username).first(10) })
      end

      # Read once per issue for as long as this provider lives.
      def files_of(raw)
        (@files ||= {})[raw[:id]] ||= begin
          found = uploads_in(raw[:description], raw, { "kind" => "description" }, restricted: raw[:confidential])
          api.all_notes(raw[:project_id], raw[:iid]).each do |note|
            found.concat(uploads_in(note[:body], raw, { "kind" => "comment", "id" => note[:id] },
                                    restricted: raw[:confidential] || note[:internal]))
          end
          found.group_by(&:id).map { |_id, copies| copies.find { |c| !c.restricted } || copies.first }
        end
      end

      def uploads_in(text, raw, location, restricted:)
        text.to_s.scan(UPLOAD).map do |_bang, _label, url, secret, filename|
          name = URI.decode_www_form_component(filename)
          Attachment.new(id: "#{secret}/#{name}", issue_id: raw[:id], name: name,
                         origin: :embedded, location: location, restricted: restricted == true,
                         url: url.start_with?("http") ? url : "#{::Gitlab::Host.web_base}/#{raw[:key].to_s.split('#').first}#{url}")
        end
      end
    end
  end
end
