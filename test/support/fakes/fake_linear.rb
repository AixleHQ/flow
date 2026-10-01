# frozen_string_literal: true

# In-memory fake of Linear::Api (docs/testing.md R3). Callers — the tracker
# provider, tools, the pipeline, the connect flow — get it from `stub_linear!`.
# The return shapes are the ones test/services/linear/api_test.rb pins the real
# adapter to against Linear's GraphQL payloads (R4).
#
# Workspace Acme: team ENG with five workflow states, team OPS, and ENG-1 in
# "Ready for AI".
module FakeLinear
  class Api
    ORGANIZATION = "6b1a3f0e-0000-4000-8000-00000000acme"
    ENG = "0f3c2a10-1111-4000-8000-000000000e00"
    OPS = "0f3c2a10-2222-4000-8000-000000000f00"
    BOT_ID = "9d7e5c3b-0000-4000-8000-0000000000b0"
    ISSUE_1 = "a1b2c3d4-0000-4000-8000-000000000001"

    STATES = [
      { id: "st-backlog", name: "Backlog", type: "backlog" },
      { id: "st-ready", name: "Ready for AI", type: "unstarted" },
      { id: "st-progress", name: "In Progress", type: "started" },
      { id: "st-done", name: "Done", type: "completed" },
      { id: "st-canceled", name: "Canceled", type: "canceled" }
    ].freeze
    TEAMS = [
      { id: ENG, key: "ENG", name: "Engineering" },
      { id: OPS, key: "OPS", name: "Operations" }
    ].freeze
    MEMBERS = [
      { id: "5e1f0000-0000-4000-8000-0000000000ad", name: "Ada Lovelace", display_name: "ada", email: "ada@example.com", app: false },
      { id: "5e1f0000-0000-4000-8000-0000000000ab", name: "Ada Byron", display_name: "byron", email: "byron@example.com", app: false },
      { id: BOT_ID, name: "Aixle Bot", display_name: "aixle", email: "bot@example.com", app: false }
    ].freeze
    LABELS = [ { id: "lb-bug", name: "Bug" }, { id: "lb-ai", name: "ai" } ].freeze

    attr_reader :calls, :comments_by_issue, :webhooks
    attr_accessor :me

    def initialize
      @calls = []
      @me = { id: BOT_ID, name: "Aixle Bot", display_name: "aixle", email: "bot@example.com", app: false,
              organization: { id: ORGANIZATION, name: "Acme", url_key: "acme" } }
      @issues = {}
      @comments_by_issue = Hash.new { |h, k| h[k] = [] }
      @webhooks = {}
      @next = 100
      @failures = {}
      add_issue(id: ISSUE_1, key: "ENG-1", title: "It breaks", state_id: "st-ready", team: TEAMS[0])
      add_issue(id: "a1b2c3d4-0000-4000-8000-000000000002", key: "OPS-1", title: "Rotate keys", state_id: "st-backlog", team: TEAMS[1])
    end

    def add_issue(id:, key:, title:, state_id:, team:, description: nil, labels: [], assignee: nil)
      @issues[id] = {
        id: id, key: key, number: key.split("-").last.to_i, title: title, description: description,
        url: "https://linear.app/acme/issue/#{key}/slug", priority: 0, updated_at: "2026-10-01T10:00:00.000Z",
        team_id: team[:id], team_key: team[:key], state: STATES.find { |s| s[:id] == state_id }.dup,
        assignee: assignee, labels: labels
      }
    end

    # The next call to `method` raises `error`.
    def fail_next(method, error)
      @failures[method] = error
    end

    def calls_to(method) = @calls.select { |c| c[:method] == method }
    def called?(method) = calls_to(method).any?

    def identity = record(:identity) { @me.deep_dup }
    def teams = record(:teams) { TEAMS.map(&:dup) }
    def states(team_id) = record(:states, team_id: team_id) { STATES.map(&:dup) }
    def labels(team_id) = record(:labels, team_id: team_id) { LABELS.map(&:dup) }

    def members(team_id, query: nil)
      record(:members, team_id: team_id, query: query) do
        MEMBERS.select do |m|
          query.blank? || [ m[:name], m[:display_name], m[:email] ].any? { |v| v.downcase.include?(query.to_s.downcase) }
        end.map(&:dup)
      end
    end

    def issue(ref)
      record(:issue, ref: ref) do
        found = @issues[ref.to_s] || @issues.values.find { |i| i[:key].casecmp?(ref.to_s) }
        found || raise(Trackers::Error.new("Entity not found: Issue", code: "not_found"))
        found.deep_dup
      end
    end

    def issues(filter:, limit:, cursor: nil)
      record(:issues, filter: filter, limit: limit, cursor: cursor) do
        team = filter.dig(:and, 0, :team, :id, :eq)
        { issues: @issues.values.select { |i| i[:team_id] == team }.map(&:deep_dup), next_cursor: nil }
      end
    end

    def create_issue(input)
      record(:create_issue, input: input) do
        team = TEAMS.find { |t| t[:id] == input[:teamId] }
        id = format("a1b2c3d4-0000-4000-8000-%012d", @next += 1)
        add_issue(id: id, key: "#{team[:key]}-#{@next}", title: input[:title], description: input[:description],
                  state_id: input[:stateId] || "st-backlog", team: team,
                  labels: LABELS.select { |l| Array(input[:labelIds]).include?(l[:id]) })
        apply_assignee(@issues[id], input) if input.key?(:assigneeId)
        @issues[id].deep_dup
      end
    end

    def update_issue(id, input)
      record(:update_issue, id: id, input: input) do
        issue = @issues.fetch(id)
        issue[:title] = input[:title] if input.key?(:title)
        issue[:description] = input[:description] if input.key?(:description)
        issue[:state] = STATES.find { |s| s[:id] == input[:stateId] }.dup if input.key?(:stateId)
        issue[:priority] = input[:priority] if input.key?(:priority)
        issue[:labels] = LABELS.select { |l| input[:labelIds].include?(l[:id]) } if input.key?(:labelIds)
        issue[:labels] |= LABELS.select { |l| Array(input[:addedLabelIds]).include?(l[:id]) }
        issue[:labels] -= LABELS.select { |l| Array(input[:removedLabelIds]).include?(l[:id]) }
        apply_assignee(issue, input) if input.key?(:assigneeId)
        issue.deep_dup
      end
    end

    def comments(issue_id, limit:, cursor: nil)
      record(:comments, issue_id: issue_id, limit: limit, cursor: cursor) do
        { comments: @comments_by_issue[issue_id].map(&:dup), next_cursor: nil }
      end
    end

    def create_comment(issue_id, body)
      record(:create_comment, issue_id: issue_id, body: body) do
        comment = { id: "cm-#{@next += 1}", body: body, created_at: "2026-10-01T10:05:00.000Z", author: "aixle" }
        @comments_by_issue[issue_id] << comment
        comment.dup
      end
    end

    def create_webhook(url:, team_id:, secret:, label:)
      record(:create_webhook, url: url, team_id: team_id, secret: secret, label: label) do
        id = "wh-#{@next += 1}"
        @webhooks[id] = { url: url, team_id: team_id, secret: secret }
        id
      end
    end

    def delete_webhook(id)
      record(:delete_webhook, id: id) { !@webhooks.delete(id).nil? }
    end

    private

    def apply_assignee(issue, input)
      member = MEMBERS.find { |m| m[:id] == input[:assigneeId] }
      issue[:assignee] = member && member.slice(:id, :name, :display_name, :email)
    end

    def record(method, **args)
      @calls << { method: method, **args }
      error = @failures.delete(method)
      raise error if error

      yield
    end
  end
end

# Linear in tests: `with_linear_oauth_app` configures the deployment's OAuth
# app, `stub_linear!` hands every Linear::Api the one FakeLinear::Api it
# returns. Linear::Client, Credential and Oauth stay real and are
# contract-tested against WebMock in test/services/linear/.
module LinearTestHelper
  LINEAR_API = "https://api.linear.app"

  def with_linear_oauth_app(client_id: "linear-app-client", client_secret: "linear-app-secret",
                            webhook_secret: "linear-app-webhook-secret", webhook_base_url: "https://flow.example.com")
    Settings.stubs(:linear).returns(Hashie::Mash.new(client_id: client_id, client_secret: client_secret,
                                                     webhook_secret: webhook_secret, webhook_base_url: webhook_base_url))
  end

  def stub_linear!
    fake = FakeLinear::Api.new
    Linear::Api.stubs(:new).returns(fake)
    fake
  end

  # A delivery as Linear signs it: the hex HMAC of the exact body.
  def linear_signature(body, secret)
    OpenSSL::HMAC.hexdigest("SHA256", secret, body)
  end
end
