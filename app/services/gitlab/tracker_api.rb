# frozen_string_literal: true

module Gitlab
  # The GitLab REST operations the tracker uses, one method each, answering
  # with plain hashes (docs/design/gitlab-tracker.md §5).
  #
  # An issue is addressed by its project and iid: GitLab looks an issue up by
  # its global id for administrators only, so the pair is what Flow keeps.
  class TrackerApi
    NOTE_PAGES = 5

    def self.for(integration) = new(Rest.for(integration))

    def initialize(rest)
      @rest = rest
    end

    def me
      raw = @rest.get("/user")
      { id: raw["id"].to_s, username: raw["username"], name: raw["name"] }
    end

    def project(id_or_path)
      raw = @rest.get("/projects/#{escape(id_or_path)}")
      { id: raw["id"].to_s, path: raw["path_with_namespace"], name: raw["name_with_namespace"], web_url: raw["web_url"] }
    end

    # The project's boards, each with its label lists in board order:
    # [{ id:, name:, lists: [label names] }]. Lists of another kind (assignee,
    # milestone, iteration) are left out: they are not a status.
    def boards(project_id)
      Array(@rest.get("/projects/#{escape(project_id)}/boards")).map do |board|
        lists = Array(board["lists"]).select { |l| l["label"].is_a?(Hash) }.sort_by { |l| l["position"].to_i }
        { id: board["id"].to_s, name: board["name"].presence || "Board", lists: lists.map { |l| l.dig("label", "name") } }
      end
    end

    def issue(project_id, iid)
      normalize(@rest.get("/projects/#{escape(project_id)}/issues/#{iid.to_i}"))
    end

    # One page: { issues:, next_page: }.
    def issues(project_id, params:, page:, per_page:)
      raw = @rest.get("/projects/#{escape(project_id)}/issues", params.merge(page: page, per_page: per_page))
      list = Array(raw).map { |i| normalize(i) }
      { issues: list, next_page: list.size == per_page ? page + 1 : nil }
    end

    def create_issue(project_id, attributes)
      normalize(@rest.post("/projects/#{escape(project_id)}/issues", attributes))
    end

    def update_issue(project_id, iid, attributes)
      normalize(@rest.put("/projects/#{escape(project_id)}/issues/#{iid.to_i}", attributes))
    end

    # People's comments, oldest first; GitLab's own system notes are left out.
    def notes(project_id, iid, page:, per_page:)
      raw = @rest.get("/projects/#{escape(project_id)}/issues/#{iid.to_i}/notes",
                      { sort: "asc", order_by: "created_at", page: page, per_page: per_page })
      list = Array(raw)
      { notes: list.reject { |n| n["system"] }.map { |n| note(n) }, next_page: list.size == per_page ? page + 1 : nil }
    end

    def all_notes(project_id, iid)
      page = 1
      notes = []
      NOTE_PAGES.times do
        result = notes(project_id, iid, page: page, per_page: 100)
        notes.concat(result[:notes])
        break unless (page = result[:next_page])
      end
      notes
    end

    def add_note(project_id, iid, body)
      note(@rest.post("/projects/#{escape(project_id)}/issues/#{iid.to_i}/notes", { body: body.to_s }))
    end

    # [{ id:, username:, name: }]
    def members(project_id, query: nil)
      @rest.paginate("/projects/#{escape(project_id)}/members/all", { query: query.presence }.compact, limit: 100).map do |m|
        { id: m["id"].to_s, username: m["username"], name: m["name"] }
      end
    end

    def create_hook(project_id, url:, token:)
      raw = @rest.post("/projects/#{escape(project_id)}/hooks",
                       { url: url, token: token, issues_events: true, note_events: true, push_events: false,
                         enable_ssl_verification: true })
      raw["id"].to_s
    end

    def delete_hook(project_id, hook_id)
      @rest.delete("/projects/#{escape(project_id)}/hooks/#{hook_id.to_i}")
      true
    rescue Trackers::Error => e
      raise unless e.code == "not_found"

      false
    end

    # { secret:, filename:, url:, markdown: } of a file now in the project's uploads.
    def upload(project_id, file)
      raw = @rest.upload("/projects/#{escape(project_id)}/uploads", file)
      secret, filename = raw["url"].to_s.match(%r{/uploads/(\h{32})/([^/]+)\z})&.captures
      raise Trackers::Error.new("GitLab did not say where it put the file", code: "provider_error") unless secret

      { secret: secret, filename: URI.decode_www_form_component(filename), url: raw["url"], markdown: raw["markdown"],
        full_path: raw["full_path"] }
    end

    def download(project_id, secret, filename, io:, max_bytes:)
      @rest.download("/projects/#{escape(project_id)}/uploads/#{secret}/#{ERB::Util.url_encode(filename)}",
                     io: io, max_bytes: max_bytes)
    end

    private

    def escape(value) = ERB::Util.url_encode(value.to_s)

    def normalize(raw)
      return if raw.blank? || raw["iid"].blank?

      project_id = raw["project_id"].to_s
      {
        id: "#{project_id}:#{raw['iid']}", global_id: raw["id"].to_s, iid: raw["iid"].to_i, project_id: project_id,
        key: raw.dig("references", "full").presence || "#{project_id}##{raw['iid']}", url: raw["web_url"],
        title: raw["title"], description: raw["description"], state: raw["state"], type: raw["issue_type"],
        labels: Array(raw["labels"]).map { |l| l.is_a?(Hash) ? l["name"] : l.to_s },
        assignees: Array(raw["assignees"]).map { |a| { id: a["id"].to_s, username: a["username"], name: a["name"] } },
        confidential: raw["confidential"] == true, updated_at: raw["updated_at"]
      }
    end

    def note(raw)
      { id: raw["id"].to_s, body: raw["body"].to_s, author: raw.dig("author", "username"), created_at: raw["created_at"],
        internal: raw["internal"] == true || raw["confidential"] == true }
    end
  end
end
