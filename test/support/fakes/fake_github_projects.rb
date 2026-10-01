# frozen_string_literal: true

# In-memory fake of Github::ProjectsApi (docs/testing.md R3). Callers — the
# tracker provider, tools, the pipeline, the projects picker — get it from
# `stub_github_projects!`. The return shapes are the ones
# test/services/github/projects_api_test.rb pins the real adapter to (R4).
#
# Organization acme-corp: the Roadmap project, whose Status field has four
# columns, and the Ops project. acme-corp/app#1 is on Roadmap in "Ready for AI";
# acme-corp/app#2 is on no board.
module FakeGithub
  class ProjectsApi
    ROADMAP = "PVT_kwDOroadmap"
    OPS = "PVT_kwDOops"
    STATUS_FIELD = { id: "PVTSSF_status", name: "Status", options: [
      { id: "opt-todo", name: "Todo" }, { id: "opt-ready", name: "Ready for AI" },
      { id: "opt-progress", name: "In Progress" }, { id: "opt-done", name: "Done" }
    ] }.freeze
    PROJECTS = [
      { id: ROADMAP, number: 1, title: "Roadmap", url: "https://github.com/orgs/acme-corp/projects/1", closed: false },
      { id: OPS, number: 2, title: "Ops", url: "https://github.com/orgs/acme-corp/projects/2", closed: false }
    ].freeze

    attr_reader :calls, :contents, :comments_by_content

    def initialize
      @calls = []
      @contents = {}
      @comments_by_content = Hash.new { |h, k| h[k] = [] }
      @next = 100
      @failures = {}
      add_issue(id: "I_kwDOissue1", number: 1, title: "It breaks", status: "Ready for AI")
      add_issue(id: "I_kwDOissue2", number: 2, title: "Not on a board", status: nil, project: nil)
    end

    def add_issue(id:, number:, title:, status:, project: ROADMAP, repository: "acme-corp/app", body: nil, labels: [], assignees: [])
      option = STATUS_FIELD[:options].find { |o| o[:name] == status }
      @contents[id] = {
        id: id, number: number, key: "#{repository}##{number}", url: "https://github.com/#{repository}/issues/#{number}",
        title: title, body: body, state: "OPEN", state_reason: nil, type: "Issue", pull_request: false,
        repository: repository, updated_at: "2026-10-01T10:00:00Z", assignees: assignees, labels: labels,
        placements: project ? [ { item_id: "PVTI_#{id}", project_id: project, status: status, option_id: option&.dig(:id) } ] : []
      }
    end

    # The next call to `method` raises `error`.
    def fail_next(method, error)
      @failures[method] = error
    end

    def calls_to(method) = @calls.select { |c| c[:method] == method }
    def called?(method) = calls_to(method).any?

    def projects(login)
      record(:projects, login: login) { PROJECTS.map(&:dup) }
    end

    def project(project_id, field:)
      record(:project, id: project_id, field: field) do
        project = PROJECTS.find { |p| p[:id] == project_id } || raise(Trackers::Error.new("no project", code: "not_found"))
        project.slice(:id, :number, :title, :url).merge(owner: "acme-corp", field: field == "Status" ? STATUS_FIELD.deep_dup : nil)
      end
    end

    def issue_types(login)
      record(:issue_types, login: login) { [ { id: "IT_bug", name: "Bug" } ] }
    end

    def content(node_id, field:)
      record(:content, id: node_id, field: field) { @contents[node_id]&.deep_dup }
    end

    def content_by_number(owner:, repo:, number:, field:)
      record(:content_by_number, owner: owner, repo: repo, number: number.to_i, field: field) do
        @contents.values.find { |c| c[:repository].casecmp?("#{owner}/#{repo}") && c[:number] == number.to_i }&.deep_dup
      end
    end

    def items(project_id, query:, field:, limit:, cursor: nil)
      record(:items, id: project_id, query: query, field: field, limit: limit, cursor: cursor) do
        on_board = @contents.values.select { |c| c[:placements].any? { |p| p[:project_id] == project_id } }
        items = on_board.map { |c| c.deep_dup.merge(placements: c[:placements].select { |p| p[:project_id] == project_id }) }
        { items: items, next_cursor: nil }
      end
    end

    def comments(node_id, limit:, cursor: nil)
      record(:comments, id: node_id, limit: limit, cursor: cursor) do
        { comments: @comments_by_content[node_id].map(&:dup), next_cursor: nil }
      end
    end

    def add_comment(node_id, body)
      record(:add_comment, id: node_id, body: body) do
        comment = { id: "IC_#{@next += 1}", body: body, created_at: "2026-10-01T10:05:00Z", author: "aixle-flow[bot]" }
        @comments_by_content[node_id] << comment
        comment.dup
      end
    end

    def set_status(project_id:, item_id:, field_id:, option_id:)
      record(:set_status, project_id: project_id, item_id: item_id, field_id: field_id, option_id: option_id) do
        option = STATUS_FIELD[:options].find { |o| o[:id] == option_id }
        @contents.each_value do |content|
          content[:placements].each { |p| p.merge!(status: option[:name], option_id: option_id) if p[:item_id] == item_id }
        end
        true
      end
    end

    def add_to_project(project_id, content_id)
      record(:add_to_project, project_id: project_id, content_id: content_id) do
        item = "PVTI_#{content_id}"
        @contents.fetch(content_id)[:placements] << { item_id: item, project_id: project_id, status: nil, option_id: nil }
        item
      end
    end

    def create_issue(repository, title:, body: nil, assignees: [], labels: [], type: nil)
      record(:create_issue, repository: repository, title: title, body: body, assignees: assignees, labels: labels, type: type) do
        number = @next += 1
        id = "I_kwDOnew#{number}"
        add_issue(id: id, number: number, title: title, body: body, status: nil, project: nil, repository: repository,
                  labels: labels, assignees: assignees)
        @contents[id][:type] = type if type
        { node_id: id, key: "#{repository}##{number}" }
      end
    end

    def update_issue(repository, number, attributes)
      record(:update_issue, repository: repository, number: number, attributes: attributes) do
        content = find!(repository, number)
        content[:title] = attributes[:title] if attributes.key?(:title)
        content[:body] = attributes[:body] if attributes.key?(:body)
        content[:state] = attributes[:state].upcase if attributes.key?(:state)
        # GitHub drops anyone who cannot be assigned in the repository.
        content[:assignees] = Array(attributes[:assignees]).reject { |l| l == "outsider" } if attributes.key?(:assignees)
        {}
      end
    end

    def set_labels(repository, number, labels)
      record(:set_labels, repository: repository, number: number, labels: labels) { find!(repository, number)[:labels] = labels }
    end

    def add_labels(repository, number, labels)
      record(:add_labels, repository: repository, number: number, labels: labels) do
        find!(repository, number)[:labels] |= labels
      end
    end

    def remove_label(repository, number, label)
      record(:remove_label, repository: repository, number: number, label: label) do
        find!(repository, number)[:labels] -= [ label ]
      end
    end

    private

    def find!(repository, number)
      @contents.values.find { |c| c[:repository] == repository && c[:number] == number.to_i } ||
        raise(Trackers::Error.new("no issue", code: "not_found"))
    end

    def record(method, **args)
      @calls << { method: method, **args }
      error = @failures.delete(method)
      raise error if error

      yield
    end
  end
end

module GithubProjectsTestHelper
  def stub_github_projects!(app_slug: "aixle-flow")
    fake = FakeGithub::ProjectsApi.new
    Github::ProjectsApi.stubs(:for).returns(fake)
    Settings.github.stubs(:app_slug).returns(app_slug)
    fake
  end
end
