# frozen_string_literal: true

# In-memory fake of Jira::Api (docs/testing.md R3). Callers — the tracker
# provider, tools, the pipeline, the connect flow — get it from `stub_jira!`.
# The return shapes are the ones test/services/jira/api_test.rb pins the real
# adapter to against recorded Jira payloads (R4); keep the two in lockstep.
#
# One site: ENG (10000) with a board whose "Ready for AI" column is its own
# status, and OPS (10001) with no board at all.
module FakeJira
  class Api
    BOT_ID = "712020:0f5a7a8e-1111-4c1b-9b9a-000000000001"

    STATUSES = {
      "1" => { id: "1", name: "To Do", category: "new" },
      "10004" => { id: "10004", name: "Ready for AI", category: "new" },
      "3" => { id: "3", name: "In Progress", category: "indeterminate" },
      "10002" => { id: "10002", name: "In Review", category: "indeterminate" },
      "10003" => { id: "10003", name: "Done", category: "done" }
    }.freeze

    COLUMNS = [
      { name: "Backlog", status_ids: [ "1" ] },
      { name: "Ready for AI", status_ids: [ "10004" ] },
      { name: "Doing", status_ids: [ "3", "10002" ] },
      { name: "Done", status_ids: [ "10003" ] }
    ].freeze

    PROJECTS = [
      { id: "10000", key: "ENG", name: "Engineering" },
      { id: "10001", key: "OPS", name: "Operations" }
    ].freeze

    USERS = [
      { id: "557058:ada", name: "Ada Lovelace", email: "ada@example.com" },
      { id: "557058:ada2", name: "Ada Byron" },
      { id: BOT_ID, name: "Aixle Bot" }
    ].freeze

    attr_reader :calls, :issues, :comments_by_issue, :webhook_registry
    attr_accessor :me

    def initialize
      @calls = []
      @me = { id: BOT_ID, name: "Aixle Bot" }
      @issues = {}
      @comments_by_issue = Hash.new { |h, k| h[k] = [] }
      @webhook_registry = {}
      @next_id = 20_000
      @failures = {}
      add_issue(id: "10100", key: "ENG-1", summary: "It breaks", status_id: "10004", project: PROJECTS[0])
      add_issue(id: "10200", key: "OPS-1", summary: "Rotate keys", status_id: "1", project: PROJECTS[1])
    end

    def add_issue(id:, key:, summary:, status_id:, project:, description: nil, labels: [], assignee: nil)
      @issues[id] = {
        id: id, key: key, summary: summary, description: description, type: "Task", status: STATUSES.fetch(status_id),
        project: project.slice(:id, :key), assignee: assignee, labels: labels, priority: "Medium", due_date: nil,
        parent: nil, components: [], created_at: "2026-09-30T10:00:00.000+0000", updated_at: "2026-09-30T10:00:00.000+0000"
      }
    end

    # The next call to `method` raises `error`.
    def fail_next(method, error)
      @failures[method] = error
    end

    def calls_to(method)
      @calls.select { |c| c[:method] == method }
    end

    def called?(method) = calls_to(method).any?

    def myself = record(:myself) { @me.dup }

    def projects(query: nil)
      record(:projects, query: query) { PROJECTS.map(&:dup) }
    end

    def project(id_or_key)
      record(:project, id: id_or_key) do
        project = find_project!(id_or_key)
        project.merge(issue_types: [ { id: "1", name: "Task", subtask: false }, { id: "2", name: "Bug", subtask: false } ])
      end
    end

    def statuses(project_id)
      record(:statuses, project_id: project_id) do
        find_project!(project_id)
        %w[Task Bug].map { |type| { issue_type: type, statuses: STATUSES.values.map(&:dup) } }
      end
    end

    def boards(project_id)
      record(:boards, project_id: project_id) { project_id.to_s == "10000" ? [ { id: "7", name: "ENG board", type: "kanban" } ] : [] }
    end

    def board_columns(board_id)
      record(:board_columns, board_id: board_id) { COLUMNS.map(&:dup) }
    end

    def issue(id_or_key)
      record(:issue, id: id_or_key) { find_issue!(id_or_key).deep_dup }
    end

    def search(jql:, limit: 50, cursor: nil)
      record(:search, jql: jql, limit: limit, cursor: cursor) do
        project = jql[/project = (\d+)/, 1]
        { issues: @issues.values.select { |i| i[:project][:id] == project }.map(&:deep_dup), next_cursor: nil }
      end
    end

    def create_issue(fields)
      record(:create_issue, fields: fields) do
        id = (@next_id += 1).to_s
        project = PROJECTS.find { |p| p[:id] == fields.dig(:project, :id) }
        add_issue(id: id, key: "#{project[:key]}-#{id}", summary: fields[:summary], status_id: "1", project: project,
                  description: fields[:description], labels: Array(fields[:labels]))
        { id: id, key: @issues[id][:key] }
      end
    end

    def update_issue(id, fields: {}, update: {})
      record(:update_issue, id: id, fields: fields, update: update) do
        issue = find_issue!(id)
        issue[:summary] = fields[:summary] if fields.key?(:summary)
        issue[:description] = fields[:description] if fields.key?(:description)
        issue[:labels] = fields[:labels] if fields.key?(:labels)
        Array(update[:labels]).each do |op|
          op[:add] ? issue[:labels] |= [ op[:add] ] : issue[:labels] -= [ op[:remove] ]
        end
        nil
      end
    end

    # Every status is reachable from every other, like a simplified workflow.
    def transitions(id)
      record(:transitions, id: id) do
        current = find_issue!(id)[:status][:id]
        STATUSES.values.reject { |s| s[:id] == current }.map { |s| { id: "t#{s[:id]}", name: "Move to #{s[:name]}", to: s.dup } }
      end
    end

    def transition(id, transition_id)
      record(:transition, id: id, transition_id: transition_id) do
        find_issue!(id)[:status] = STATUSES.fetch(transition_id.delete_prefix("t"))
        nil
      end
    end

    def assign(id, account_id)
      record(:assign, id: id, account_id: account_id) do
        find_issue!(id)[:assignee] = account_id && USERS.find { |u| u[:id] == account_id }&.slice(:id, :name)
        nil
      end
    end

    def comments(id, limit: 50, cursor: nil)
      record(:comments, id: id, limit: limit, cursor: cursor) do
        list = @comments_by_issue[find_issue!(id)[:id]]
        start = cursor.to_i
        page = list[start, limit] || []
        { comments: page, next_cursor: start + page.size < list.size ? (start + page.size).to_s : nil }
      end
    end

    def add_comment(id, body)
      record(:add_comment, id: id, body: body) do
        comment = { id: (@next_id += 1).to_s, author: @me[:name], body: body, created_at: "2026-09-30T11:00:00.000+0000" }
        @comments_by_issue[find_issue!(id)[:id]] << comment
        comment
      end
    end

    def assignable_users(project_key:, query:)
      record(:assignable_users, project_key: project_key, query: query) do
        USERS.select { |u| u[:name].downcase.include?(query.downcase) || u[:email].to_s.casecmp?(query) }.map(&:dup)
      end
    end

    def register_webhook(url:, jql:, events:)
      record(:register_webhook, url: url, jql: jql, events: events) do
        id = (@next_id += 1).to_s
        @webhook_registry[id] = { id: id, jql: jql, events: events, expires_at: 30.days.from_now.iso8601 }
        id
      end
    end

    def webhooks
      record(:webhooks) { @webhook_registry.values.map(&:dup) }
    end

    def refresh_webhooks(ids)
      record(:refresh_webhooks, ids: ids) do
        missing = ids.map(&:to_s) - @webhook_registry.keys
        raise Jira::Error.new("Webhook not found", code: "not_found", status: 404) if missing.any?

        30.days.from_now.change(usec: 0)
      end
    end

    def delete_webhooks(ids)
      record(:delete_webhooks, ids: ids) do
        ids.each { |id| @webhook_registry.delete(id.to_s) }
        nil
      end
    end

    private

    def record(method, **args)
      @calls << { method: method }.merge(args)
      failure = @failures.delete(method)
      raise failure if failure

      yield
    end

    def find_project!(id_or_key)
      PROJECTS.find { |p| p[:id] == id_or_key.to_s || p[:key] == id_or_key.to_s }&.dup ||
        raise(Jira::Error.new("No project could be found", code: "not_found", status: 404))
    end

    def find_issue!(id_or_key)
      @issues[id_or_key.to_s] || @issues.values.find { |i| i[:key] == id_or_key.to_s } ||
        raise(Jira::Error.new("Issue does not exist or you do not have permission to see it", code: "not_found", status: 404))
    end
  end
end
