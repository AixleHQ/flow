# frozen_string_literal: true

module PullRequests
  module Bitbucket
    # Bitbucket Cloud pull requests behind the pull-request port
    # (docs/design/bitbucket-integration.md §4.11).
    #
    # Every call is addressed by the repository's workspace and repository UUID,
    # never by its slug, so a rename cannot send it to whatever owns the old name
    # and a pull request id of another repository is unreachable.
    class Provider < PullRequests::Provider
      STATES = { "OPEN" => "open", "MERGED" => "merged", "DECLINED" => "closed", "SUPERSEDED" => "closed" }.freeze
      STRATEGIES = { "merge_commit" => "merge_commit", "squash" => "squash", "fast_forward" => "fast_forward" }.freeze
      CI_STATES = { "SUCCESSFUL" => "passed", "FAILED" => "failed", "STOPPED" => "failed", "INPROGRESS" => "pending" }.freeze
      MERGE_TASK_POLLS = 3

      def list(repository, state: "open", source_branch: nil, cursor: nil, limit: 20)
        unless ::Bitbucket::Api::STATES.key?(state.presence || "open")
          raise invalid("state must be one of #{::Bitbucket::Api::STATES.keys.join(', ')}")
        end

        items, next_cursor = call do
          api.pull_requests(*address(repository), state: state.presence || "open", source_branch: source_branch.presence,
                                                  cursor: cursor.presence, limit: limit)
        end
        Page.new(items: items.map { |pr| pull_request(repository, pr) }, next_cursor: next_cursor)
      end

      def get(repository, ref)
        pull_request(repository, fetch(repository, number_of(repository, ref)))
      end

      def changes(repository, ref, cursor: nil, limit: 50)
        items, next_cursor = call { api.diffstat(*address(repository), number_of(repository, ref), cursor: cursor.presence, limit: limit) }
        Page.new(items: items.map { |change| file_change(change) }, next_cursor: next_cursor)
      end

      def create(repository, source_branch:, target_branch:, title:, description: nil, draft: true)
        pr = call do
          api.create_pull_request(*address(repository), title: title, source_branch: source_branch,
                                                        target_branch: target_branch, description: description,
                                                        draft: draft != false)
        end
        pull_request(repository, pr)
      end

      def update(repository, ref, title: nil, description: nil, target_branch: nil, draft: nil, state: nil)
        id = number_of(repository, ref)
        current = fetch(repository, id)
        status = STATES.fetch(current[:state].to_s, "closed")
        raise invalid("state must be open or closed") unless state.blank? || %w[open closed].include?(state.to_s)
        if status != "open" && (state.to_s == "open" || title || description || target_branch || !draft.nil?)
          raise Error::Conflict.new("Pull request ##{id} is #{status}; Bitbucket changes and reopens only open ones",
                                    details: { state: status })
        end

        if title || !description.nil? || target_branch || !draft.nil?
          current = call do
            api.update_pull_request(*address(repository), id, title: title.presence || current[:title],
                                                              description: description, target_branch: target_branch,
                                                              draft: draft)
          end
        end
        current = call { api.decline_pull_request(*address(repository), id) } if state.to_s == "closed" && status == "open"
        pull_request(repository, current)
      end

      def list_comments(repository, ref, cursor: nil, limit: 50)
        items, next_cursor = call do
          api.comments(*address(repository), number_of(repository, ref), cursor: cursor.presence, limit: limit)
        end
        Page.new(items: items.map { |c| comment(c) }, next_cursor: next_cursor)
      end

      def add_comment(repository, ref, body:, file_path: nil, line: nil, reply_to: nil)
        raise invalid("line is required with file_path") if file_path.present? && line.blank?

        created = call do
          api.create_comment(*address(repository), number_of(repository, ref), body: body, path: file_path.presence,
                                                                               line: line, parent_id: reply_to.presence)
        end
        comment(created)
      end

      def review(repository, ref, verdict:, body: nil)
        id = number_of(repository, ref)
        participant = call do
          case verdict.to_s
          when "approve" then api.approve(*address(repository), id)
          when "unapprove" then api.unapprove(*address(repository), id)
          when "request_changes" then api.request_changes(*address(repository), id)
          else raise invalid("verdict must be approve, unapprove or request_changes")
          end
        end
        add_comment(repository, id, body: body) if body.present?
        Review.new(reviewer: participant&.dig(:user).presence || integration.name, verdict: verdict.to_s,
                   submitted_at: time(participant&.dig(:participated_on)) || Time.current)
      end

      # Bitbucket's merge takes no expected commit, so the head is compared here
      # (the guard Azure turned out to need too). A push landing between the read
      # and the merge is the one window left, one request long.
      def merge(repository, ref, expected_head_sha:, strategy: nil, delete_source_branch: false, message: nil)
        id = number_of(repository, ref)
        current = pull_request(repository, fetch(repository, id))
        return MergeResult.new(merged: true, already_merged: true, pending: false, pull_request: current) if current.merged?
        raise Error::Conflict.new("Pull request ##{id} is closed", details: { state: current.state }) unless current.open?

        guard_head!(current, expected_head_sha)
        answer = merging(current) do
          api.merge_pull_request(*address(repository), id, strategy: merge_strategy(strategy),
                                                           close_source_branch: (true if delete_source_branch),
                                                           message: message)
        end
        return merged_result(repository, answer[:pull_request]) if answer[:pull_request]

        await_merge(repository, id, answer[:task_id])
      end

      def checks(repository, ref)
        pr = fetch(repository, number_of(repository, ref))
        head = pr[:source_commit]
        statuses = head.present? ? call { api.commit_statuses(*address(repository), head) } : []
        items = statuses.map { |s| { name: s[:name], status: CI_STATES.fetch(s[:state].to_s, "pending"), url: s[:url] } }
        Checks.new(state: overall(items), head_sha: head, items: items)
      end

      def owns_reference?(repository, ref)
        prefix = "#{::Bitbucket::AppConfig::WEB_HOST}/#{repository.full_name}/pull-requests/".downcase
        ref.to_s.downcase.start_with?(prefix) && ref.to_s[prefix.length..].to_s.match?(%r{\A\d+(?:[/?#].*)?\z})
      end

      def number_of(repository, ref)
        text = ref.to_s.strip
        return text.to_i if text.match?(/\A\d+\z/)
        return text.delete_prefix("#").to_i if text.match?(/\A#\d+\z/)
        return text[%r{/pull-requests/(\d+)}, 1].to_i if owns_reference?(repository, text)

        raise invalid("#{ref.inspect} is not a pull request of #{repository.full_name}")
      end

      private

      def api = @api ||= ::Bitbucket::Api.for(integration)

      def address(repository)
        workspace = repository.external_organization_id.presence
        uuid = repository.external_id.presence
        raise invalid("#{repository.full_name} has no Bitbucket identity; attach it again") unless workspace && uuid

        [ workspace, uuid ]
      end

      def fetch(repository, id)
        pr = call { api.pull_request(*address(repository), id) }
        destination = pr[:destination_repository_uuid]
        if destination.present? && destination != ::Bitbucket::Identifiers.uuid(repository.external_id)
          raise Error.new("Pull request ##{id} is not #{repository.full_name}'s", code: "not_found_or_inaccessible")
        end

        pr
      end

      def pull_request(repository, pr)
        PullRequest.new(
          number: pr[:id], url: "#{::Bitbucket::AppConfig::WEB_HOST}/#{repository.full_name}/pull-requests/#{pr[:id]}",
          title: pr[:title], description: pr[:description], state: STATES.fetch(pr[:state].to_s, "closed"),
          draft: pr[:draft], source_branch: pr[:source_branch], target_branch: pr[:destination_branch],
          head_sha: pr[:source_commit], author: pr[:author], reviewers: pr[:reviewers], mergeable: nil,
          created_at: time(pr[:created_on]), updated_at: time(pr[:updated_on])
        )
      end

      def comment(c)
        Comment.new(id: c[:id], parent_id: c[:parent_id], author: c[:author], body: c[:body], file_path: c[:path],
                    line: c[:line], resolved: c[:resolved], created_at: time(c[:created_on]))
      end

      def file_change(change)
        FileChange.new(path: change[:path], old_path: (change[:old_path] if change[:status] == "renamed"),
                       status: change[:status], additions: change[:additions], deletions: change[:deletions])
      end

      def guard_head!(pull_request, expected)
        return if pull_request.head_sha.present? && ::Bitbucket::Identifiers.same_commit?(pull_request.head_sha, expected)

        raise Error::Conflict.new("Pull request ##{pull_request.number} has moved since it was reviewed",
                                  details: { current_head_sha: pull_request.head_sha, expected_head_sha: expected })
      end

      def merge_strategy(strategy)
        return nil if strategy.blank?

        STRATEGIES.fetch(strategy.to_s) { raise invalid("strategy must be one of #{STRATEGIES.keys.join(', ')}") }
      end

      # 400 is Bitbucket refusing the merge as things stand (approvals, merge
      # checks, conflicts); 409 is a ref moving under the merge.
      def merging(current)
        call { yield }
      rescue Error => e
        case e.code
        when "conflict"
          raise Error::Conflict.new("Pull request ##{current.number} moved before Bitbucket merged it",
                                    details: { current_head_sha: current.head_sha })
        when "validation_failed"
          raise Error.new("Bitbucket will not merge ##{current.number} now: #{e.message}", code: "not_mergeable")
        else raise e
        end
      end

      def await_merge(repository, id, task_id)
        if task_id.present?
          MERGE_TASK_POLLS.times do
            sleep(::Bitbucket::AppConfig.merge_poll_interval)
            task = call { api.merge_task(*address(repository), id, task_id) }
            return merged_result(repository, task[:pull_request]) if task[:status] == "SUCCESS" && task[:pull_request]
          end
        end

        current = pull_request(repository, fetch(repository, id))
        MergeResult.new(merged: current.merged?, already_merged: false, pending: !current.merged?, pull_request: current)
      end

      def merged_result(repository, pr)
        merged = pull_request(repository, pr)
        MergeResult.new(merged: merged.merged?, already_merged: false, pending: !merged.merged?, pull_request: merged)
      end

      def overall(items)
        states = items.map { |item| item[:status] }
        return "none" if states.empty?
        return "failed" if states.include?("failed")
        return "pending" if states.include?("pending")

        "passed"
      end

      def call
        yield
      rescue ::Bitbucket::Error::OutcomeUnknown => e
        raise Error::OutcomeUnknown, e.message
      rescue ::Bitbucket::Error::Conflict => e
        raise Error::Conflict.new(e.message, details: e.details)
      rescue ::Bitbucket::Error => e
        raise Error.from(e)
      end

      def invalid(message) = Error.new(message, code: "validation_failed")

      def time(value) = value.present? ? Time.zone.parse(value.to_s) : nil
    end
  end
end
