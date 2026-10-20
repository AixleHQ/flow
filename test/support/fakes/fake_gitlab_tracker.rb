# frozen_string_literal: true

# In-memory fake of Gitlab::TrackerApi (docs/testing.md R3). Callers — the
# tracker provider, tools, the pipeline, the connect flow — get it from
# `stub_gitlab_tracker!`. The return shapes are the ones
# test/services/gitlab/tracker_api_test.rb pins the real adapter to (R4).
#
# Project acme/app (id 501) with one board whose label lists are
# "Ready for AI" and "Doing"; acme/app#1 is open and labelled "Ready for AI".
module FakeGitlab
  class TrackerApi
    PROJECT = "501"
    PATH = "acme/app"
    BOARD = "71"
    LISTS = [ "Ready for AI", "Doing" ].freeze
    BOT = { id: "900", username: "aixle-flow-ab12", name: "Aixle Flow" }.freeze
    MEMBERS = [
      { id: "11", username: "ada", name: "Ada Lovelace" },
      { id: "12", username: "adam", name: "Adam Smith" },
      BOT
    ].freeze

    attr_reader :calls, :stored_issues, :notes_by_issue, :hooks, :uploads

    def initialize
      @calls = []
      @stored_issues = {}
      @notes_by_issue = Hash.new { |h, k| h[k] = [] }
      @hooks = {}
      @uploads = {}
      @next = 100
      @failures = {}
      add_issue(iid: 1, title: "It breaks", labels: [ "Ready for AI", "bug" ])
    end

    def add_issue(iid:, title:, labels: [], state: "opened", description: nil, confidential: false, project: PROJECT, path: PATH)
      @stored_issues["#{project}:#{iid}"] = {
        id: "#{project}:#{iid}", global_id: (@next += 1).to_s, iid: iid, project_id: project, key: "#{path}##{iid}",
        url: "https://gitlab.com/#{path}/-/issues/#{iid}", title: title, description: description, state: state,
        type: "issue", labels: labels, assignees: [], confidential: confidential, updated_at: "2026-10-20T10:00:00.000Z"
      }
    end

    # A file someone uploaded to the project; returns its Markdown link target.
    def add_upload(name:, bytes:)
      secret = SecureRandom.hex(16)
      @uploads["#{secret}/#{name}"] = bytes.b
      "/uploads/#{secret}/#{name}"
    end

    def add_note_by(iid, body:, internal: false)
      note = { id: (@next += 1).to_s, body: body, author: "ada", created_at: "2026-10-20T10:05:00.000Z", internal: internal }
      @notes_by_issue["#{PROJECT}:#{iid}"] << note
      note
    end

    def fail_next(method, error)
      @failures[method] = error
    end

    def calls_to(method) = @calls.select { |c| c[:method] == method }
    def called?(method) = calls_to(method).any?

    def me = record(:me) { BOT.dup }

    def boards(project_id)
      record(:boards, project_id: project_id) { project_id.to_s == PROJECT ? [ { id: BOARD, name: "Development", lists: LISTS.dup } ] : [] }
    end

    def issue(project_id, iid)
      record(:issue, project_id: project_id, iid: iid) { @stored_issues["#{project_id}:#{iid.to_i}"]&.deep_dup || raise(not_found) }
    end

    def issues(project_id, params:, page:, per_page:)
      record(:issues, project_id: project_id, params: params, page: page) do
        { issues: @stored_issues.values.select { |i| i[:project_id] == project_id.to_s }.map(&:deep_dup), next_page: nil }
      end
    end

    def create_issue(project_id, attributes)
      record(:create_issue, project_id: project_id, attributes: attributes) do
        iid = @stored_issues.size + 1
        add_issue(iid: iid, title: attributes[:title], labels: attributes[:labels].to_s.split(","), description: attributes[:description])
        @stored_issues["#{project_id}:#{iid}"].deep_dup
      end
    end

    def update_issue(project_id, iid, attributes)
      record(:update_issue, project_id: project_id, iid: iid, attributes: attributes) do
        issue = @stored_issues.fetch("#{project_id}:#{iid.to_i}")
        issue[:title] = attributes[:title] if attributes.key?(:title)
        issue[:labels] = attributes[:labels].to_s.split(",") if attributes.key?(:labels)
        issue[:labels] |= attributes[:add_labels].to_s.split(",") if attributes[:add_labels]
        issue[:labels] -= attributes[:remove_labels].to_s.split(",") if attributes[:remove_labels]
        issue[:state] = "closed" if attributes[:state_event] == "close"
        issue[:state] = "opened" if attributes[:state_event] == "reopen"
        if attributes.key?(:assignee_ids)
          issue[:assignees] = MEMBERS.select { |m| attributes[:assignee_ids].map(&:to_s).include?(m[:id]) }.map(&:dup)
        end
        issue.deep_dup
      end
    end

    def notes(project_id, iid, page:, per_page:)
      record(:notes, project_id: project_id, iid: iid, page: page) do
        { notes: @notes_by_issue["#{project_id}:#{iid.to_i}"].map(&:dup), next_page: nil }
      end
    end

    def all_notes(project_id, iid) = notes(project_id, iid, page: 1, per_page: 100)[:notes]

    def add_note(project_id, iid, body)
      record(:add_note, project_id: project_id, iid: iid, body: body) do
        note = { id: (@next += 1).to_s, body: body, author: BOT[:username], created_at: "2026-10-20T10:06:00.000Z", internal: false }
        @notes_by_issue["#{project_id}:#{iid.to_i}"] << note
        note.dup
      end
    end

    def members(project_id, query: nil)
      record(:members, project_id: project_id, query: query) do
        MEMBERS.select { |m| query.blank? || m[:username].include?(query.to_s) || m[:name].downcase.include?(query.to_s.downcase) }.map(&:dup)
      end
    end

    def create_hook(project_id, url:, token:)
      record(:create_hook, project_id: project_id, url: url) do
        id = (@next += 1).to_s
        @hooks[id] = { project_id: project_id, url: url, token: token }
        id
      end
    end

    def delete_hook(project_id, hook_id)
      record(:delete_hook, project_id: project_id, hook_id: hook_id) { !@hooks.delete(hook_id.to_s).nil? }
    end

    def upload(project_id, file)
      record(:upload, project_id: project_id, name: file.filename) do
        secret = SecureRandom.hex(16)
        @uploads["#{secret}/#{file.filename}"] = file.io.read
        { secret: secret, filename: file.filename, url: "/uploads/#{secret}/#{file.filename}",
          markdown: "[#{file.filename}](/uploads/#{secret}/#{file.filename})", full_path: "/-/project/#{project_id}/uploads/#{secret}/#{file.filename}" }
      end
    end

    def download(project_id, secret, filename, io:, max_bytes:)
      record(:download, project_id: project_id, secret: secret, filename: filename) do
        bytes = @uploads.fetch("#{secret}/#{filename}") { raise not_found }
        raise Trackers::Error.new("The file is larger than allowed", code: "too_large") if bytes.bytesize > max_bytes

        io.write(bytes)
        { content_type: "application/octet-stream", size: bytes.bytesize }
      end
    end

    private

    def not_found = Trackers::Error.new("GitLab has no such resource", code: "not_found")

    def record(method, **args)
      @calls << { method: method, **args }
      error = @failures.delete(method)
      raise error if error

      yield
    end
  end
end

# GitLab issues in tests: `stub_gitlab_tracker!` hands every
# Gitlab::TrackerApi.for the one FakeGitlab::TrackerApi it returns.
# Gitlab::Rest and Gitlab::TrackerApi stay real in their WebMock contract tests.
module GitlabTrackerTestHelper
  def stub_gitlab_tracker!
    fake = FakeGitlab::TrackerApi.new
    Gitlab::TrackerApi.stubs(:for).returns(fake)
    fake
  end

  # A service-account connection tracking acme/app on its board.
  def gitlab_tracker_integration(company: create(:company), project: nil)
    project ||= create(:project, company: company, owner: create(:user, company: company))
    create(:integration, :gitlab, :active, company: company, project: project).tap do |integration|
      integration.update!(settings: integration.settings.to_h.merge(
        "auth_mode" => "service_account", "gitlab_user_id" => FakeGitlab::TrackerApi::BOT[:id],
        "gitlab_username" => FakeGitlab::TrackerApi::BOT[:username],
        "gitlab_trackers" => [ { "id" => FakeGitlab::TrackerApi::PROJECT, "path" => FakeGitlab::TrackerApi::PATH,
                                 "name" => "Acme / App", "board_id" => FakeGitlab::TrackerApi::BOARD, "board_name" => "Development" } ]
      ))
    end
  end
end

ActiveSupport::TestCase.include(GitlabTrackerTestHelper)
