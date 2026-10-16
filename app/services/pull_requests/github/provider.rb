# frozen_string_literal: true

module PullRequests
  module Github
    # GitHub pull requests behind the pull-request port, over Octokit with the
    # connection's credential: an installation token narrowed to the one
    # repository for an App connection, the stored token for a PAT one.
    #
    # Everything is addressed by `owner/repo`, so a pull request number of
    # another repository is unreachable, and URLs are built from that name rather
    # than taken from a response.
    class Provider < PullRequests::Provider
      WEB_HOST = "https://github.com"
      LIST_STATES = { "open" => "open", "closed" => "closed", "merged" => "closed", "all" => "all" }.freeze
      MERGE_METHODS = { "merge_commit" => "merge", "squash" => "squash", "fast_forward" => "rebase" }.freeze
      PASSED_CHECKS = %w[success neutral skipped].freeze
      DEFAULT_CHANGES_REQUESTED = "Changes requested."

      def list(repository, state: "open", source_branch: nil, cursor: nil, limit: 20)
        filter = state.presence || "open"
        raise invalid("state must be one of #{LIST_STATES.keys.join(', ')}") unless LIST_STATES.key?(filter)

        page = page_number(cursor)
        pulls = read do
          client(repository).pull_requests(repository.full_name, {
            state: LIST_STATES.fetch(filter), head: (head_filter(repository, source_branch) if source_branch.present?),
            sort: "updated", direction: "desc", per_page: limit, page: page
          }.compact)
        end
        pulls = pulls.select { |pr| merged_at(pr).present? } if filter == "merged"
        pulls = pulls.reject { |pr| merged_at(pr).present? } if filter == "closed"
        Page.new(items: pulls.map { |pr| pull_request(repository, pr) }, next_cursor: next_page(repository, page))
      end

      def get(repository, ref)
        pull_request(repository, fetch(repository, number_of(repository, ref)))
      end

      def changes(repository, ref, cursor: nil, limit: 50)
        page = page_number(cursor)
        files = read do
          client(repository).pull_request_files(repository.full_name, number_of(repository, ref), per_page: limit, page: page)
        end
        Page.new(items: files.map { |file| file_change(file) }, next_cursor: next_page(repository, page))
      end

      def create(repository, source_branch:, target_branch:, title:, description: nil, draft: true)
        pr = write do
          client(repository).create_pull_request(repository.full_name, target_branch, source_branch, title, description,
                                                 draft: draft != false)
        end
        pull_request(repository, pr)
      end

      def update(repository, ref, title: nil, description: nil, target_branch: nil, draft: nil, state: nil)
        number = number_of(repository, ref)
        current = fetch(repository, number)
        raise invalid("state must be open or closed") unless state.blank? || %w[open closed].include?(state.to_s)
        if merged_at(current).present? && (state.present? || title || target_branch || !draft.nil?)
          raise Error::Conflict.new("Pull request ##{number} is merged", details: { state: "merged" })
        end

        changes = { title: title.presence, body: description, base: target_branch.presence, state: state.presence }.compact
        current = write { client(repository).update_pull_request(repository.full_name, number, changes) } if changes.any?
        current = toggle_draft(repository, current, draft) unless draft.nil? || draft == (current[:draft] == true)
        pull_request(repository, current)
      end

      # Conversation comments and review (inline) comments are two lists on
      # GitHub; one page of each, merged in time order.
      def list_comments(repository, ref, cursor: nil, limit: 50)
        number = number_of(repository, ref)
        page = page_number(cursor)
        conversation = read { client(repository).issue_comments(repository.full_name, number, per_page: limit, page: page) }
        more = next_page(repository, page)
        inline = read { client(repository).pull_request_comments(repository.full_name, number, per_page: limit, page: page) }
        more ||= next_page(repository, page)
        comments = conversation.map { |c| comment(c) } + inline.map { |c| comment(c, inline: true) }
        Page.new(items: comments.sort_by { |c| [ c.created_at || Time.zone.at(0), c.id.to_i ] }, next_cursor: more)
      end

      def add_comment(repository, ref, body:, file_path: nil, line: nil, reply_to: nil)
        number = number_of(repository, ref)
        raise invalid("line is required with file_path") if file_path.present? && line.blank?

        if reply_to.present? && (parent = review_comment(repository, number, reply_to))
          created = write do
            client(repository).create_pull_request_comment_reply(repository.full_name, number, body, parent[:id])
          end
          return comment(created, inline: true)
        end

        if file_path.present?
          head = fetch(repository, number).dig(:head, :sha)
          created = write do
            client(repository).create_pull_request_comment(repository.full_name, number, body, head, file_path,
                                                           line.to_i, side: "RIGHT")
          end
          return comment(created, inline: true)
        end

        # A conversation comment has no thread on GitHub, so a reply to one is a
        # new conversation comment.
        comment(write { client(repository).add_comment(repository.full_name, number, body) })
      end

      def review(repository, ref, verdict:, body: nil)
        number = number_of(repository, ref)
        review = case verdict.to_s
        when "approve" then submit_review(repository, number, "APPROVE", body)
        when "request_changes" then submit_review(repository, number, "REQUEST_CHANGES", body.presence || DEFAULT_CHANGES_REQUESTED)
        when "unapprove" then withdraw_approval(repository, number)
        else raise invalid("verdict must be approve, unapprove or request_changes")
        end
        Review.new(reviewer: login_of(review[:user]) || acting_login, verdict: verdict.to_s,
                   submitted_at: time(review[:submitted_at]) || Time.current)
      end

      def merge(repository, ref, expected_head_sha:, strategy: nil, delete_source_branch: false, message: nil)
        number = number_of(repository, ref)
        raw = fetch(repository, number)
        current = pull_request(repository, raw)
        return MergeResult.new(merged: true, already_merged: true, pending: false, pull_request: current) if current.merged?
        raise Error::Conflict.new("Pull request ##{number} is closed", details: { state: current.state }) unless current.open?

        guard_head!(current, expected_head_sha)
        merging(current, expected_head_sha) do
          client(repository).merge_pull_request(repository.full_name, number, message.to_s,
                                                { sha: current.head_sha, merge_method: merge_method(strategy) }.compact)
        end
        delete_head_branch(repository, raw) if delete_source_branch
        merged = get(repository, number)
        MergeResult.new(merged: merged.merged?, already_merged: false, pending: !merged.merged?, pull_request: merged)
      end

      def checks(repository, ref)
        head = fetch(repository, number_of(repository, ref)).dig(:head, :sha)
        statuses = commit_statuses(repository, head)
        runs = read { client(repository).check_runs_for_ref(repository.full_name, head, per_page: 100) }

        items = Array(statuses[:statuses]).map do |status|
          { name: status[:context], status: status_state(status[:state]), url: status[:target_url] }
        end
        items += Array(runs[:check_runs]).map do |run|
          { name: run[:name], status: check_run_state(run), url: run[:html_url] }
        end
        Checks.new(state: overall(items), head_sha: head, items: items)
      end

      def owns_reference?(repository, ref)
        prefix = "#{WEB_HOST}/#{repository.full_name}/pull/".downcase
        ref.to_s.downcase.start_with?(prefix) && ref.to_s[prefix.length..].to_s.match?(%r{\A\d+(?:[/?#].*)?\z})
      end

      def number_of(repository, ref)
        text = ref.to_s.strip
        return text.to_i if text.match?(/\A\d+\z/)
        return text.delete_prefix("#").to_i if text.match?(/\A#\d+\z/)
        return text[%r{/pull/(\d+)}, 1].to_i if owns_reference?(repository, text)

        raise invalid("#{ref.inspect} is not a pull request of #{repository.full_name}")
      end

      private

      # The Aixle App does not ask for the Commit statuses permission, so an App
      # connection cannot read them; its check runs still say what CI did.
      def commit_statuses(repository, head)
        read { client(repository).combined_status(repository.full_name, head) }
      rescue Error => e
        raise unless %w[permission_denied not_found_or_inaccessible].include?(e.code)

        {}
      end

      # One client per repository: an App connection's token is narrowed to it.
      def client(repository)
        @clients ||= {}
        @clients[repository.id] ||= Octokit::Client.new(access_token: token_for(repository))
      end

      def token_for(repository)
        ::Github::TokenService.new(integration).generate_installation_token(repositories: [ repository.repo_name ])
      rescue ::Github::TokenService::ConfigurationError => e
        raise Error.new("This GitHub connection cannot authenticate: #{e.message}", code: "integration_unavailable")
      rescue ::Github::TokenService::UnavailableError => e
        raise Error.new("GitHub could not be reached: #{e.message}", code: "provider_error")
      rescue ::Github::TokenService::AuthenticationError => e
        raise Error.new("GitHub refused this connection: #{e.message}", code: "not_authorized")
      end

      def fetch(repository, number)
        read { client(repository).pull_request(repository.full_name, number) }
      end

      def web_url(repository, number) = "#{WEB_HOST}/#{repository.full_name}/pull/#{number}"

      def pull_request(repository, pr)
        PullRequest.new(
          number: pr[:number], url: web_url(repository, pr[:number]), title: pr[:title], description: pr[:body],
          state: state_of(pr), draft: pr[:draft] == true,
          source_branch: pr.dig(:head, :ref), target_branch: pr.dig(:base, :ref), head_sha: pr.dig(:head, :sha),
          author: login_of(pr[:user]), reviewers: Array(pr[:requested_reviewers]).map { |r| login_of(r) }.compact,
          mergeable: pr[:mergeable], created_at: time(pr[:created_at]), updated_at: time(pr[:updated_at])
        )
      end

      def state_of(pr)
        return "merged" if merged_at(pr).present? || pr[:merged] == true

        pr[:state].to_s == "open" ? "open" : "closed"
      end

      def merged_at(pr) = pr[:merged_at]

      def head_filter(repository, branch) = "#{repository.owner_name}:#{branch}"

      def file_change(file)
        status = case file[:status].to_s
        when "added" then "added"
        when "removed" then "removed"
        when "renamed" then "renamed"
        else "modified"
        end
        FileChange.new(path: file[:filename], old_path: file[:previous_filename], status: status,
                       additions: file[:additions], deletions: file[:deletions])
      end

      def comment(raw, inline: false)
        Comment.new(id: raw[:id], parent_id: (raw[:in_reply_to_id] if inline), author: login_of(raw[:user]),
                    body: raw[:body], file_path: (raw[:path] if inline), line: (raw[:line] || raw[:original_line] if inline),
                    resolved: nil, created_at: time(raw[:created_at]))
      end

      # The inline comment `id` names, if it is one of this pull request's;
      # nil for a conversation comment, which GitHub does not thread.
      def review_comment(repository, number, id)
        found = client(repository).pull_request_comment(repository.full_name, id)
        found if found[:pull_request_url].to_s.end_with?("/pulls/#{number}")
      rescue Octokit::NotFound
        nil
      rescue Octokit::Error, Faraday::Error => e
        translate_error(e, write: false)
      end

      def submit_review(repository, number, event, body)
        write { client(repository).create_pull_request_review(repository.full_name, number, { event: event, body: body.presence }.compact) }
      rescue Error => e
        raise e unless e.code == "validation_failed"

        # GitHub refuses a review of your own pull request with a 422.
        raise Error.new("GitHub will not take this review: #{e.message}", code: "permission_denied")
      end

      # GitHub has no "unapprove": the connection's latest approval is dismissed,
      # which needs the right to dismiss reviews on this repository.
      def withdraw_approval(repository, number)
        reviews = read { client(repository).pull_request_reviews(repository.full_name, number, per_page: 100) }
        approval = reviews.reverse.find { |r| r[:state].to_s == "APPROVED" && login_of(r[:user]).to_s.casecmp?(acting_login.to_s) }
        raise invalid("This connection has no approval on pull request ##{number} to withdraw") unless approval

        write do
          client(repository).dismiss_pull_request_review(repository.full_name, number, approval[:id], "Approval withdrawn")
        end
      end

      def acting_login
        integration.github_pat? ? integration.github_account_login : "#{Settings.github.app_slug}[bot]"
      end

      # Draft state changes only through GraphQL.
      def toggle_draft(repository, pr, draft)
        mutation = draft ? "convertPullRequestToDraft" : "markPullRequestReadyForReview"
        # A JSON string, not a Hash: Octokit reads a `query:` key as URL parameters.
        body = { query: "mutation($id: ID!) { #{mutation}(input: {pullRequestId: $id}) { pullRequest { isDraft } } }",
                 variables: { id: pr[:node_id] } }.to_json
        response = write { client(repository).post("graphql", body) }
        errors = Array(response[:errors])
        raise Error.new("GitHub refused to change the draft state: #{errors.first[:message]}", code: "validation_failed") if errors.any?

        fetch(repository, pr[:number])
      end

      def guard_head!(pull_request, expected)
        given = expected.to_s.strip.downcase
        head = pull_request.head_sha.to_s.downcase
        return if given.length >= 7 && head.start_with?(given)

        raise Error::Conflict.new("Pull request ##{pull_request.number} has moved since it was reviewed",
                                  details: { current_head_sha: pull_request.head_sha, expected_head_sha: expected })
      end

      def merge_method(strategy)
        return nil if strategy.blank?

        MERGE_METHODS.fetch(strategy.to_s) { raise invalid("strategy must be one of #{MERGE_METHODS.keys.join(', ')}") }
      end

      # 405 is GitHub saying the pull request cannot be merged now (conflicts,
      # required reviews or checks, a draft); 409 is its own `sha` guard firing.
      def merging(current, expected)
        write { yield }
      rescue Error => e
        case e.code
        when "conflict"
          raise Error::Conflict.new("Pull request ##{current.number} moved before GitHub merged it",
                                    details: { expected_head_sha: expected })
        when "not_mergeable", "validation_failed"
          raise Error.new("GitHub will not merge ##{current.number} now: #{e.message}", code: "not_mergeable")
        else raise e
        end
      end

      # Only a branch of the repository itself: a fork's branch is not ours to delete.
      def delete_head_branch(repository, pr)
        return unless pr.dig(:head, :repo, :full_name).to_s.casecmp?(repository.full_name)

        client(repository).delete_branch(repository.full_name, pr.dig(:head, :ref))
      rescue Octokit::Error, Faraday::Error => e
        Rails.logger.warn("[PullRequests::Github] merged ##{pr[:number]} but kept its branch: #{e.class}: #{e.message}")
      end

      def status_state(state)
        case state.to_s
        when "success" then "passed"
        when "pending" then "pending"
        else "failed"
        end
      end

      def check_run_state(run)
        return "pending" unless run[:status].to_s == "completed"

        PASSED_CHECKS.include?(run[:conclusion].to_s) ? "passed" : "failed"
      end

      def overall(items)
        states = items.map { |item| item[:status] }
        return "none" if states.empty?
        return "failed" if states.include?("failed")
        return "pending" if states.include?("pending")

        "passed"
      end

      def page_number(cursor)
        number = cursor.to_s.to_i
        number.positive? ? number : 1
      end

      def next_page(repository, page)
        client(repository).last_response&.rels&.[](:next) ? (page + 1).to_s : nil
      end

      def login_of(user) = user && user[:login]

      def time(value)
        return nil if value.blank?

        value.is_a?(Time) ? value.in_time_zone : Time.zone.parse(value.to_s)
      end

      def invalid(message) = Error.new(message, code: "validation_failed")

      def read(&) = translate(write: false, &)
      def write(&) = translate(write: true, &)

      def translate(write:)
        yield
      rescue Octokit::Error, Faraday::Error => e
        translate_error(e, write: write)
      end

      def translate_error(error, write:)
        case error
        when Octokit::NotFound
          raise Error.new("GitHub has no such repository or pull request, or this connection cannot see it",
                          code: "not_found_or_inaccessible")
        when Octokit::Unauthorized then raise Error.new("GitHub rejected this connection's token", code: "not_authorized")
        when Octokit::TooManyRequests, Octokit::AbuseDetected
          raise Error.new("GitHub is rate-limiting this connection", code: "rate_limited")
        when Octokit::Forbidden then raise Error.new("GitHub denied this operation: #{github_message(error)}", code: "permission_denied")
        when Octokit::Conflict then raise Error::Conflict, github_message(error)
        when Octokit::MethodNotAllowed then raise Error.new(github_message(error), code: "not_mergeable")
        when Octokit::UnprocessableEntity, Octokit::BadRequest then raise Error.new(github_message(error), code: "validation_failed")
        when Octokit::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError
          # A write with no answer may have landed; reissuing it is how duplicates get made.
          raise Error::OutcomeUnknown, "GitHub did not confirm the request (#{error.class.name.demodulize})" if write

          raise Error.new("GitHub could not be reached (#{error.class.name.demodulize})", code: "provider_error")
        else raise Error.new(github_message(error), code: "provider_error")
        end
      end

      # Octokit folds the method, URL and status into its message; GitHub's own
      # text is the part worth showing an agent.
      def github_message(error)
        error.message.to_s.sub(/\A\w+ \S+: \d+ - /, "").sub(%r{\s*// See: \S+\s*\z}, "").squish.truncate(300)
      end
    end
  end
end
