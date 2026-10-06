# frozen_string_literal: true

module Youtrack
  # The YouTrack REST operations Aixle uses, one method each, answering with
  # plain hashes. YouTrack returns only the fields a request names, so every
  # call names them.
  class Api
    USER = "id,login,fullName,email,banned"
    VALUE = "$type,id,name,login,fullName,isResolved,text,presentation"
    ISSUE = "id,idReadable,summary,description,created,updated,resolved,project(id,shortName,name)," \
            "reporter(#{USER}),tags(id,name),customFields($type,name,value(#{VALUE}))"
    COMMENT = "id,text,created,deleted,author(#{USER})"
    PROJECT_FIELD = "$type,field(name,fieldType(id)),bundle(values(id,name,isResolved,archived,ordinal),aggregatedUsers(#{USER}))"
    ACTIVITY = "id,timestamp,author(#{USER}),field(name,presentation),added(#{VALUE}),removed(#{VALUE})"
    PAGE = 100
    MAX_PAGES = 10

    def self.for(integration)
      new(Client.new(base_url: integration.settings.to_h["base_url"],
                     token: integration.credentials_data["permanent_token"]))
    end

    def initialize(client)
      @client = client
    end

    def me
      user(@client.get("/api/users/me", fields: USER))
    end

    # Projects the token's account can see, archived ones left out: [{ id:, key:, name: }].
    def projects
      paged { |skip| @client.get("/api/admin/projects", fields: "id,shortName,name,archived", "$top": PAGE, "$skip": skip) }
        .reject { |p| p["archived"] }
        .map { |p| { id: p["id"].to_s, key: p["shortName"].to_s, name: p["name"].to_s } }
    end

    # The project's custom fields: [{ name:, field_type:, values: [{ id:, name:, resolved: }], users: [...] }].
    # `field_type` is YouTrack's own ("state[1]", "enum[*]", "user[1]", …).
    def project_fields(project_id)
      list(@client.get("/api/admin/projects/#{escape(project_id)}/customFields", fields: PROJECT_FIELD, "$top": 200)).map do |f|
        bundle = f["bundle"].to_h
        {
          name: f.dig("field", "name").to_s, field_type: f.dig("field", "fieldType", "id").to_s,
          values: Array(bundle["values"]).reject { |v| v["archived"] }.sort_by { |v| v["ordinal"].to_i }
                                         .map { |v| { id: v["id"].to_s, name: v["name"].to_s, resolved: v["isResolved"] == true } },
          users: Array(bundle["aggregatedUsers"]).reject { |u| u["banned"] }.map { |u| user(u) }
        }
      end
    end

    # By database id (2-17) or readable id (APP-17).
    def issue(ref)
      issue_from(@client.get("/api/issues/#{escape(ref)}", fields: ISSUE))
    end

    def issues(query:, top:, skip:)
      list(@client.get("/api/issues", query: query, fields: ISSUE, "$top": top, "$skip": skip)).map { |raw| issue_from(raw) }
    end

    def create_issue(body)
      issue_from(@client.post("/api/issues", body, fields: ISSUE))
    end

    def update_issue(id, body)
      issue_from(@client.post("/api/issues/#{escape(id)}", body, fields: ISSUE))
    end

    # Tags the token's account can see or use: [{ id:, name: }].
    def tags
      paged { |skip| @client.get("/api/tags", fields: "id,name", "$top": PAGE, "$skip": skip) }
        .map { |t| { id: t["id"].to_s, name: t["name"].to_s } }
    end

    def add_tag(issue_id, tag_id)
      @client.post("/api/issues/#{escape(issue_id)}/tags", { id: tag_id.to_s }, fields: "id,name")
    end

    def remove_tag(issue_id, tag_id)
      @client.delete("/api/issues/#{escape(issue_id)}/tags/#{escape(tag_id)}")
    end

    def comments(issue_id, top:, skip:)
      list(@client.get("/api/issues/#{escape(issue_id)}/comments", fields: COMMENT, "$top": top, "$skip": skip))
        .reject { |c| c["deleted"] }.map { |c| comment_from(c) }
    end

    def comment(issue_id, comment_id)
      raw = @client.get("/api/issues/#{escape(issue_id)}/comments/#{escape(comment_id)}", fields: COMMENT)
      raw["deleted"] ? nil : comment_from(raw)
    end

    def add_comment(issue_id, text)
      comment_from(@client.post("/api/issues/#{escape(issue_id)}/comments", { text: text.to_s }, fields: COMMENT))
    end

    # The issue's latest custom-field changes, newest first:
    # [{ id:, at:, author:, field:, added: [names], removed: [names] }].
    def field_activities(issue_id, top: 50)
      list(@client.get("/api/issues/#{escape(issue_id)}/activities", categories: "CustomFieldCategory", reverse: true,
                                                                       fields: ACTIVITY, "$top": top)).map do |a|
        { id: a["id"].to_s, at: time(a["timestamp"]), author: a["author"] && user(a["author"]),
          field: (a.dig("field", "name").presence || a.dig("field", "presentation")).to_s, added: names(a["added"]), removed: names(a["removed"]) }
      end
    end

    private

    # A list endpoint answers an array; anything else is no items, not a list of key/value pairs.
    def list(result) = result.is_a?(Array) ? result : []

    def paged
      items = []
      MAX_PAGES.times do |page|
        batch = list(yield(page * PAGE))
        items.concat(batch)
        break if batch.size < PAGE
      end
      items
    end

    def issue_from(raw)
      return if raw.blank? || raw["id"].blank?

      {
        id: raw["id"].to_s, key: raw["idReadable"].to_s, title: raw["summary"], description: raw["description"],
        created_at: time(raw["created"]), updated_at: time(raw["updated"]), resolved: raw["resolved"].present?,
        project_id: raw.dig("project", "id").to_s, project_key: raw.dig("project", "shortName").to_s,
        reporter: raw["reporter"] && user(raw["reporter"]),
        tags: Array(raw["tags"]).map { |t| { id: t["id"].to_s, name: t["name"].to_s } },
        custom_fields: Array(raw["customFields"]).map { |f| { name: f["name"].to_s, type: f["$type"].to_s, value: value(f["value"]) } }
      }
    end

    def comment_from(raw)
      { id: raw["id"].to_s, text: raw["text"].to_s, created_at: time(raw["created"]), author: raw["author"] && user(raw["author"]) }
    end

    def user(raw)
      { id: raw["id"].to_s, login: raw["login"].to_s, name: raw["fullName"].presence || raw["login"].to_s, email: raw["email"] }.compact
    end

    # A custom field's value: nil, a scalar, a user, a bundle element
    # ({ name:, resolved: }), a text ({ text: }), or a list of these.
    def value(raw)
      case raw
      when Array then raw.map { |v| value(v) }
      when Hash
        if raw["login"] then user(raw)
        elsif raw.key?("text") && raw["name"].nil? then { text: raw["text"] }
        elsif raw["name"].nil? && raw["presentation"] then { name: raw["presentation"].to_s }
        else { id: raw["id"].to_s, name: raw["name"].to_s, resolved: raw["isResolved"] == true }
        end
      else raw
      end
    end

    def names(raw)
      Array(raw.is_a?(Hash) ? [ raw ] : raw).filter_map do |v|
        v.is_a?(Hash) ? (v["name"].presence || v["login"].presence || v["presentation"].presence) : v.to_s.presence
      end
    end

    def time(millis)
      Time.zone.at(millis.to_i / 1000.0).iso8601(3) if millis.present?
    end

    def escape(value) = CGI.escapeURIComponent(value.to_s)
  end
end
