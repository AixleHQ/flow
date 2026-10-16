# frozen_string_literal: true

module PullRequests
  module Gitlab
    # GitLab merge requests behind the pull-request port, over the `gitlab` gem
    # client of the connection's token (docs/design/bitbucket-integration.md §4.11).
    #
    # Everything is addressed by the repository's project path, so a merge
    # request that is not this repository's cannot be reached by its iid.
    class Provider < PullRequests::Provider
      STATES = { "opened" => "open", "merged" => "merged", "closed" => "closed", "locked" => "closed" }.freeze
      LIST_STATES = { "open" => "opened", "merged" => "merged", "closed" => "closed", "all" => "all" }.freeze
      DRAFT_PREFIX = /\A\s*(?:\[draft\]|\(draft\)|draft:|draft\s+-)\s*/i
      # A merge request still deciding (or being recomputed) has no verdict yet.
      UNDECIDED_MERGE_STATUSES = %w[checking unchecked preparing approvals_syncing cannot_be_merged_recheck].freeze
      PENDING_CI = %w[created waiting_for_resource preparing pending running scheduled manual].freeze
      PASSED_CI = %w[success skipped].freeze

      def list(repository, state: "open", source_branch: nil, cursor: nil, limit: 20)
        page = page_number(cursor)
        response = read do
          client.merge_requests(project_path(repository), {
            state: LIST_STATES.fetch(state.presence || "open") { raise invalid("state must be one of #{LIST_STATES.keys.join(', ')}") },
            source_branch: source_branch.presence, order_by: "updated_at", per_page: limit, page: page
          }.compact)
        end
        Page.new(items: response.map { |mr| pull_request(repository, mr) }, next_cursor: next_page_cursor(response, page))
      end

      def get(repository, ref)
        pull_request(repository, fetch(repository, number_of(repository, ref)))
      end

      def changes(repository, ref, cursor: nil, limit: 50)
        page = page_number(cursor)
        response = read do
          client.merge_request_diffs(project_path(repository), number_of(repository, ref), per_page: limit, page: page)
        end
        Page.new(items: response.map { |diff| file_change(diff) }, next_cursor: next_page_cursor(response, page))
      end

      def create(repository, source_branch:, target_branch:, title:, description: nil, draft: true)
        mr = write do
          client.create_merge_request(project_path(repository), titled(title, draft),
                                      { source_branch: source_branch, target_branch: target_branch,
                                        description: description }.compact)
        end
        pull_request(repository, mr)
      end

      def update(repository, ref, title: nil, description: nil, target_branch: nil, draft: nil, state: nil)
        iid = number_of(repository, ref)
        current = fetch(repository, iid)
        if current.state == "merged" && state.present?
          raise Error::Conflict.new("Merge request !#{iid} is merged and cannot be reopened or closed",
                                    details: { state: "merged" })
        end

        changes = { description: description, target_branch: target_branch, state_event: state_event(state) }
        if title.present? || !draft.nil?
          changes[:title] = titled(title.presence || current.title, draft.nil? ? draft?(current) : draft)
        end
        mr = write { client.update_merge_request(project_path(repository), iid, changes.compact) }
        pull_request(repository, mr)
      end

      def list_comments(repository, ref, cursor: nil, limit: 50)
        page = page_number(cursor)
        response = read do
          client.merge_request_discussions(project_path(repository), number_of(repository, ref), per_page: limit, page: page)
        end
        comments = response.flat_map { |discussion| discussion_comments(discussion) }
        Page.new(items: comments, next_cursor: next_page_cursor(response, page))
      end

      def add_comment(repository, ref, body:, file_path: nil, line: nil, reply_to: nil)
        iid = number_of(repository, ref)
        raise invalid("line is required with file_path") if file_path.present? && line.blank?

        if reply_to.present?
          discussion = discussion_of(repository, iid, reply_to)
          note = write do
            client.create_merge_request_discussion_note(project_path(repository), iid, discussion.id, body: body)
          end
          return comment(note, parent_id: discussion.notes.first&.id)
        end

        options = { body: body }
        options[:position] = position(repository, iid, file_path, line) if file_path.present?
        discussion = write { client.create_merge_request_discussion(project_path(repository), iid, options) }
        comment(Array(discussion.notes).first)
      end

      def review(repository, ref, verdict:, body: nil)
        iid = number_of(repository, ref)
        case verdict.to_s
        when "approve" then approval { write { client.approve_merge_request(project_path(repository), iid) } }
        when "unapprove" then approval { write { client.unapprove_merge_request(project_path(repository), iid) } }
        when "request_changes"
          raise Error::Unsupported, "GitLab merge requests take approve or unapprove; leave a comment to ask for changes"
        else raise invalid("verdict must be approve, unapprove or request_changes")
        end
        add_comment(repository, iid, body: body) if body.present?
        Review.new(reviewer: integration.settings.to_h["gitlab_username"].presence || integration.name,
                   verdict: verdict.to_s, submitted_at: Time.current)
      end

      def merge(repository, ref, expected_head_sha:, strategy: nil, delete_source_branch: false, message: nil)
        iid = number_of(repository, ref)
        current = pull_request(repository, fetch(repository, iid))
        return MergeResult.new(merged: true, already_merged: true, pending: false, pull_request: current) if current.merged?
        raise Error::Conflict.new("Merge request !#{iid} is closed", details: { state: current.state }) unless current.open?

        guard_head!(current, expected_head_sha)
        mr = merging(current, expected_head_sha) do
          client.accept_merge_request(project_path(repository), iid, merge_options(expected_head_sha, strategy,
                                                                                    delete_source_branch, message))
        end
        merged = pull_request(repository, mr)
        MergeResult.new(merged: merged.merged?, already_merged: false, pending: !merged.merged?, pull_request: merged)
      end

      def checks(repository, ref)
        mr = fetch(repository, number_of(repository, ref))
        statuses = mr.sha.present? ? read { client.commit_status(project_path(repository), mr.sha, per_page: 100) } : []
        pipeline = attr(mr, :head_pipeline)

        items = Array(statuses).map do |status|
          { name: status.name, status: ci_state(status.status, allow_failure: attr(status, :allow_failure) == true),
            url: attr(status, :target_url) }
        end
        Checks.new(state: overall(pipeline, items), head_sha: mr.sha, items: items)
      end

      def owns_reference?(repository, ref)
        prefix = "#{::Gitlab::Host.web_base}/#{repository.full_name}/-/merge_requests/".downcase
        ref.to_s.downcase.start_with?(prefix) && ref.to_s[prefix.length..].to_s.match?(%r{\A\d+(?:[/?#].*)?\z})
      end

      def number_of(repository, ref)
        text = ref.to_s.strip
        return text.to_i if text.match?(/\A\d+\z/)
        return text.delete_prefix("!").to_i if text.match?(/\A!\d+\z/)
        return text[%r{/-/merge_requests/(\d+)}, 1].to_i if owns_reference?(repository, text)

        raise invalid("#{ref.inspect} is not a merge request of #{repository.full_name}")
      end

      private

      def client
        @client ||= ::Gitlab::TokenService.new(integration).client
      end

      def project_path(repository) = repository.full_name

      def fetch(repository, iid)
        read { client.merge_request(project_path(repository), iid) }
      end

      def web_url(repository, iid) = "#{::Gitlab::Host.web_base}/#{repository.full_name}/-/merge_requests/#{iid}"

      def pull_request(repository, mr)
        PullRequest.new(
          number: mr.iid, url: web_url(repository, mr.iid), title: plain_title(mr.title), description: mr.description,
          state: STATES.fetch(mr.state.to_s, mr.state.to_s), draft: draft?(mr),
          source_branch: mr.source_branch, target_branch: mr.target_branch, head_sha: mr.sha,
          author: username(mr.author), reviewers: Array(attr(mr, :reviewers)).map { |r| username(r) }.compact,
          mergeable: mergeable(mr), created_at: time(mr.created_at), updated_at: time(mr.updated_at)
        )
      end

      def mergeable(mr)
        status = attr(mr, :detailed_merge_status).presence || attr(mr, :merge_status).to_s
        return true if status.in?(%w[mergeable can_be_merged])
        return nil if status.blank? || UNDECIDED_MERGE_STATUSES.include?(status)

        false
      end

      def draft?(mr)
        attr(mr, :draft) == true || attr(mr, :work_in_progress) == true || mr.title.to_s.match?(DRAFT_PREFIX)
      end

      def titled(title, draft)
        plain = plain_title(title)
        draft ? "Draft: #{plain}" : plain
      end

      def plain_title(title) = title.to_s.sub(DRAFT_PREFIX, "")

      def state_event(state)
        case state.to_s
        when "" then nil
        when "closed" then "close"
        when "open" then "reopen"
        else raise invalid("state must be open or closed")
        end
      end

      def file_change(diff)
        status = if diff.new_file then "added"
        elsif diff.deleted_file then "removed"
        elsif diff.renamed_file then "renamed"
        else "modified"
        end
        lines = diff.diff.to_s.lines
        FileChange.new(path: diff.new_path, old_path: (diff.old_path if diff.renamed_file), status: status,
                       additions: lines.count { |l| l.start_with?("+") && !l.start_with?("+++") },
                       deletions: lines.count { |l| l.start_with?("-") && !l.start_with?("---") })
      end

      def discussion_comments(discussion)
        notes = Array(discussion.notes).reject { |note| attr(note, :system) }
        first_id = notes.first&.id
        notes.map { |note| comment(note, parent_id: (first_id unless note.id == first_id)) }
      end

      def comment(note, parent_id: nil)
        position = attr(note, :position)
        Comment.new(id: note.id, parent_id: parent_id, author: username(note.author), body: note.body,
                    file_path: position && (attr(position, :new_path) || attr(position, :old_path)),
                    line: position && (attr(position, :new_line) || attr(position, :old_line)),
                    resolved: attr(note, :resolvable) ? attr(note, :resolved) == true : nil,
                    created_at: time(note.created_at))
      end

      # A reply has to land in its thread, and GitLab addresses threads by
      # discussion id, which the agent never sees: find the one holding the note.
      def discussion_of(repository, iid, note_id)
        discussions = read do
          client.merge_request_discussions(project_path(repository), iid, per_page: 100).paginate_with_limit(1000)
        end
        discussions.find { |d| Array(d.notes).any? { |n| n.id.to_s == note_id.to_s } } ||
          raise(Error.new("No comment #{note_id} on merge request !#{iid}", code: "not_found_or_inaccessible"))
      end

      def position(repository, iid, file_path, line)
        refs = attr(fetch(repository, iid), :diff_refs)
        raise invalid("GitLab has not computed this merge request's diff yet; retry shortly") if refs.blank?

        { position_type: "text", base_sha: refs.base_sha, start_sha: refs.start_sha, head_sha: refs.head_sha,
          new_path: file_path, old_path: file_path, new_line: line.to_i }
      end

      # GitLab answers an approval it will not take (the author approving their
      # own merge request, approval rules) with a 401, which would otherwise read
      # as the token being revoked.
      def approval
        yield
      rescue Error => e
        raise e unless e.code == "not_authorized"

        raise Error.new("GitLab refused this approval — its approval rules may not let this account approve it",
                        code: "permission_denied")
      end

      def guard_head!(pull_request, expected)
        return if pull_request.head_sha.present? && pull_request.head_sha == expected.to_s.strip

        raise Error::Conflict.new("Merge request !#{pull_request.number} has moved since it was reviewed",
                                  details: { current_head_sha: pull_request.head_sha, expected_head_sha: expected })
      end

      def merge_options(sha, strategy, delete_source_branch, message)
        squash = case strategy.to_s
        when "" then nil
        when "squash" then true
        when "merge_commit" then false
        when "fast_forward"
          raise Error::Unsupported, "GitLab merges with the project's merge method; use merge_commit or squash"
        else raise invalid("strategy must be merge_commit or squash")
        end
        options = { sha: sha, squash: squash, should_remove_source_branch: (true if delete_source_branch) }
        options[squash ? :squash_commit_message : :merge_commit_message] = message if message.present?
        options.compact
      end

      # 405/406/422 is GitLab saying the merge request cannot be merged now
      # (draft, conflicts, pipeline or approvals outstanding); 409 is its own
      # `sha` guard firing; 401 is a missing merge permission, not a revoked token.
      def merging(current, expected)
        write { yield }
      rescue Error => e
        case e.code
        when "conflict"
          raise Error::Conflict.new("Merge request !#{current.number} moved before GitLab merged it",
                                    details: { expected_head_sha: expected })
        when "not_mergeable", "validation_failed"
          raise Error.new("GitLab will not merge !#{current.number} now: #{e.message}", code: "not_mergeable")
        when "not_authorized" then raise Error.new("This connection may not merge !#{current.number}", code: "permission_denied")
        else raise e
        end
      end

      def overall(pipeline, items)
        states = items.map { |item| item[:status] }
        states.unshift(ci_state(pipeline.status)) if pipeline.present? && attr(pipeline, :status).present?
        return "none" if states.empty?
        return "failed" if states.include?("failed")
        return "pending" if states.include?("pending")

        "passed"
      end

      def ci_state(status, allow_failure: false)
        return "passed" if PASSED_CI.include?(status.to_s)
        return "pending" if PENDING_CI.include?(status.to_s)

        allow_failure ? "passed" : "failed"
      end

      def page_number(cursor)
        number = cursor.to_s.to_i
        number.positive? ? number : 1
      end

      def next_page_cursor(response, page)
        response.respond_to?(:next_page?) && response.next_page? ? (page + 1).to_s : nil
      end

      def username(user) = user && (attr(user, :username) || attr(user, :name))

      # The gem's ObjectifiedHash answers a missing key by forwarding to Hash
      # methods, so optional fields are read by key, never by method.
      def attr(object, name)
        object[name.to_s] if object.is_a?(::Gitlab::ObjectifiedHash) || object.is_a?(Hash)
      end

      def time(value) = value.present? ? Time.zone.parse(value.to_s) : nil

      def invalid(message) = Error.new(message, code: "validation_failed")

      def read(&) = translate(write: false, &)
      def write(&) = translate(write: true, &)

      def translate(write:)
        yield
      rescue ::Gitlab::Error::NotFound
        raise Error.new("GitLab has no such project or merge request, or this connection cannot see it",
                        code: "not_found_or_inaccessible")
      rescue ::Gitlab::Error::Unauthorized
        raise Error.new("GitLab rejected this connection's token", code: "not_authorized")
      rescue ::Gitlab::Error::Forbidden
        raise Error.new("GitLab denied this operation to this connection", code: "permission_denied")
      rescue ::Gitlab::Error::Conflict => e
        raise Error::Conflict, gitlab_message(e)
      rescue ::Gitlab::Error::MethodNotAllowed, ::Gitlab::Error::NotAcceptable => e
        raise Error.new(gitlab_message(e), code: "not_mergeable")
      rescue ::Gitlab::Error::BadRequest, ::Gitlab::Error::Unprocessable => e
        raise Error.new(gitlab_message(e), code: "validation_failed")
      rescue ::Gitlab::Error::TooManyRequests
        raise Error.new("GitLab is rate-limiting this connection", code: "rate_limited")
      rescue ::Gitlab::TokenService::ConfigurationError
        raise Error.new("This GitLab connection has no token", code: "integration_unavailable")
      rescue ::Gitlab::Error::InternalServerError, ::Gitlab::Error::BadGateway, ::Gitlab::Error::ServiceUnavailable,
             ::Gitlab::Error::ConnectionTimedOut, *::Gitlab::TokenService::NETWORK_ERRORS => e
        # A write with no answer may have landed; reissuing it is how duplicates get made.
        raise Error::OutcomeUnknown, "GitLab did not confirm the request (#{e.class.name.demodulize})" if write

        raise Error.new("GitLab could not be reached (#{e.class.name.demodulize})", code: "provider_error")
      rescue ::Gitlab::Error::Error => e
        raise Error.new(gitlab_message(e), code: "provider_error")
      end

      # The gem folds GitLab's message into "Server responded with code N,
      # message: … Request URI: …"; only the message is worth showing an agent.
      def gitlab_message(error)
        text = error.message.to_s[/message: (.*?)\. Request URI:/m, 1].presence || error.message.to_s
        text.squish.truncate(300)
      end
    end
  end
end
