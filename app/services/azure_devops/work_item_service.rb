# frozen_string_literal: true

module AzureDevops
  # Azure Boards work items — what replaces "issues" for this provider, with
  # three differences that are not cosmetic:
  #
  # 1. Work items live in an Azure PROJECT, not in a repository. A repository is
  #    not part of their address at all.
  # 2. Types and states come from the project's process. Bug, Task, User Story,
  #    Issue and any custom type are not an interchangeable hard-coded enum, and
  #    a state that is valid in one project is rejected in another.
  # 3. Fields are addressed by reference name (`System.Title`, `System.State`),
  #    and updates are JSON Patch, not a merge of a partial object.
  class WorkItemService
    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100
    # Azure's own cap on the batch endpoint. Asking for more is a 400, not a
    # silent truncation.
    BATCH_LIMIT = 200

    # The fields returned by default. An explicit list rather than everything,
    # because a work item in a customized process can carry hundreds of fields
    # and all of them would land in the agent's context.
    SUMMARY_FIELDS = %w[
      System.Id System.WorkItemType System.Title System.State System.AssignedTo
      System.Tags System.AreaPath System.IterationPath System.ChangedDate
    ].freeze

    def initialize(integration)
      @integration = integration
    end

    attr_reader :integration

    # Process metadata: which types exist here, and for each which states and
    # which required fields. Without this an agent guesses "Bug" and gets a
    # validation error it cannot interpret.
    def work_item_types
      client, resolved = client_for(:"work_items.read")
      payload = client.get("_apis", "wit", "workitemtypes", family: :wit, project: resolved.project_id)

      Array(payload["value"]).map do |type|
        {
          name: type["name"],
          reference_name: type["referenceName"],
          description: type["description"],
          states: Array(type["states"]).map { |s| { name: s["name"], category: s["category"] } },
          required_fields: Array(type["fields"]).select { |f| f["alwaysRequired"] }.map { |f| f["referenceName"] }
        }.compact
      end
    end

    # Structured filters only. WIQL is built here with the selected project
    # pinned as a predicate and every value bound through an escaper — a
    # caller-supplied WIQL fragment cannot be made safe by appending a project
    # clause to it, because the fragment can close the clause itself.
    def query(filters: {}, limit: DEFAULT_LIMIT, cursor: nil)
      client, resolved = client_for(:"work_items.read")
      wiql = build_wiql(filters, resolved.project_id)

      # WIQL has no generic $skip. Paging is done over the ORDERED id list it
      # returns, which is deterministic because the query always orders by id.
      payload = client.post("_apis", "wit", "wiql", body: { query: wiql },
                                                    family: :wit, project: resolved.project_id,
                                                    params: { "$top" => 1000 })

      ids = Array(payload["workItems"]).map { |w| w["id"].to_i }
      offset = cursor.to_i
      page = ids[offset, clamp(limit)] || []

      {
        work_items: page.any? ? hydrate(client, resolved, page) : [],
        total_matched: ids.size,
        has_more: offset + page.size < ids.size,
        next_cursor: offset + page.size < ids.size ? (offset + page.size).to_s : nil
      }.compact
    end

    def get(work_item_id)
      client, resolved = client_for(:"work_items.read")
      item = client.get("_apis", "wit", "workitems", work_item_id.to_s,
                        family: :wit, project: resolved.project_id,
                        params: { "$expand" => "relations" })

      verify_project_scope!(item, resolved)
      detail(item)
    end

    # Comments are their own API under their own preview version. System.History
    # is not a complete discussion feed and reading it instead silently drops
    # comments.
    def comments(work_item_id, limit: DEFAULT_LIMIT, cursor: nil)
      client, resolved = client_for(:"work_items.read")
      payload = client.get("_apis", "wit", "workItems", work_item_id.to_s, "comments",
                           family: :wit_comments, project: resolved.project_id,
                           params: { "$top" => clamp(limit), continuationToken: cursor.presence })

      {
        comments: Array(payload["comments"]).map do |c|
          { id: c["id"], author: c.dig("createdBy", "displayName"), text: c["text"],
            created_at: c["createdDate"], modified_at: c["modifiedDate"] }.compact
        end,
        has_more: payload["continuationToken"].present?,
        next_cursor: payload["continuationToken"].presence
      }.compact
    end

    def add_comment(work_item_id, text:)
      client, resolved = client_for(:"work_items.write")
      comment = client.post("_apis", "wit", "workItems", work_item_id.to_s, "comments",
                            body: { text: text.to_s }, family: :wit_comments, project: resolved.project_id)
      { id: comment["id"], created_at: comment["createdDate"] }.compact
    end

    # The type goes in the path with a `$` prefix — that is the API's shape, not
    # a typo. Fields are supplied as JSON Patch adds against `/fields/<ref>`.
    def create(type:, fields: {})
      client, resolved = client_for(:"work_items.write")
      patch = allowed_fields(fields).map { |ref, value| { op: "add", path: "/fields/#{ref}", value: value } }
      raise ValidationFailed, "At least System.Title is required" if patch.empty?

      item = client.post("_apis", "wit", "workitems", "$#{type}",
                         body: patch, family: :wit, project: resolved.project_id,
                         content_type: "application/json-patch+json")
      detail(item)
    end

    # `expected_revision` becomes a JSON Patch `test` on /rev, so a concurrent
    # edit makes Azure reject the whole patch rather than letting it overwrite
    # somebody's change. bypassRules is never set.
    def update(work_item_id, fields: {}, expected_revision: nil)
      client, resolved = client_for(:"work_items.write")
      patch = []
      patch << { op: "test", path: "/rev", value: expected_revision.to_i } if expected_revision.present?
      patch.concat(allowed_fields(fields).map { |ref, value| { op: "add", path: "/fields/#{ref}", value: value } })
      raise ValidationFailed, "No updatable fields supplied" if patch.none? { |p| p[:op] == "add" }

      item = client.patch("_apis", "wit", "workitems", work_item_id.to_s,
                          body: patch, family: :wit, project: resolved.project_id,
                          content_type: "application/json-patch+json")
      detail(item)
    rescue Conflict, ValidationFailed => e
      raise e unless expected_revision.present?

      current = begin
        get(work_item_id)[:rev]
      rescue StandardError
        nil
      end
      raise Conflict.new("Work item #{work_item_id} changed since revision #{expected_revision}",
                         details: { current_revision: current })
    end

    # Attaches the PR as an ArtifactLink relation. Deliberately separate from any
    # state change: a linked pull request must not close the work item by itself.
    def link_pull_request(work_item_id, artifact_id:, expected_revision: nil, comment: nil)
      client, resolved = client_for(:"work_items.write")
      patch = []
      patch << { op: "test", path: "/rev", value: expected_revision.to_i } if expected_revision.present?
      patch << {
        op: "add", path: "/relations/-",
        value: {
          rel: "ArtifactLink", url: artifact_id,
          attributes: { name: "Pull Request", comment: comment.to_s.presence }.compact
        }
      }

      item = client.patch("_apis", "wit", "workitems", work_item_id.to_s,
                          body: patch, family: :wit, project: resolved.project_id,
                          content_type: "application/json-patch+json")
      detail(item)
    rescue ValidationFailed => e
      # Azure rejects a duplicate relation. Re-adding an existing link is what
      # the caller wanted to be true, so it is a no-op rather than an error.
      raise e unless e.message.to_s.match?(/relation already exists|RelationAlreadyExists/i)

      get(work_item_id).merge(already_linked: true)
    end

    private

    def client_for(capability)
      CredentialProvider.client_for(integration, capability: capability)
    end

    def clamp(limit)
      (limit.presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
    end

    def hydrate(client, resolved, ids)
      ids.each_slice(BATCH_LIMIT).flat_map do |slice|
        payload = client.post("_apis", "wit", "workitemsbatch",
                              body: { ids: slice, fields: SUMMARY_FIELDS },
                              family: :wit, project: resolved.project_id)
        Array(payload["value"]).map { |item| summary(item) }
      end
    end

    def summary(item)
      fields = item["fields"] || {}
      {
        id: item["id"],
        rev: item["rev"],
        type: fields["System.WorkItemType"],
        title: fields["System.Title"],
        state: fields["System.State"],
        assigned_to: fields.dig("System.AssignedTo", "displayName"),
        tags: fields["System.Tags"],
        area_path: fields["System.AreaPath"],
        changed_at: fields["System.ChangedDate"]
      }.compact
    end

    def detail(item)
      summary(item).merge(
        description: item.dig("fields", "System.Description"),
        iteration_path: item.dig("fields", "System.IterationPath"),
        relations: Array(item["relations"]).map { |r| { rel: r["rel"], url: r["url"] } },
        url: item.dig("_links", "html", "href")
      ).compact
    end

    # A work item id is unique per organization, not per project, so an id from
    # a neighbouring project would otherwise read fine through this connection.
    def verify_project_scope!(item, resolved)
      project_id = item.dig("fields", "System.TeamProject")
      return if project_id.blank?
      return if project_id == resolved.project_id
      return if project_id.to_s == integration.azure_project_name.to_s

      raise NotAuthorized, "That work item is not in this connection's Azure project"
    end

    # Field reference names only, from an allowlist. An arbitrary `/fields/...`
    # path from a caller is how a tool call turns into an edit of something the
    # capability profile never enabled.
    WRITABLE_FIELDS = {
      "title" => "System.Title",
      "description" => "System.Description",
      "state" => "System.State",
      "assigned_to" => "System.AssignedTo",
      "tags" => "System.Tags",
      "area_path" => "System.AreaPath",
      "iteration_path" => "System.IterationPath",
      "priority" => "Microsoft.VSTS.Common.Priority",
      "acceptance_criteria" => "Microsoft.VSTS.Common.AcceptanceCriteria",
      "repro_steps" => "Microsoft.VSTS.TCM.ReproSteps"
    }.freeze

    def allowed_fields(fields)
      fields.to_h.filter_map do |key, value|
        next if value.nil?

        reference = WRITABLE_FIELDS[key.to_s] || (WRITABLE_FIELDS.value?(key.to_s) ? key.to_s : nil)
        raise ValidationFailed, "Field '#{key}' cannot be set through this tool" if reference.nil?

        [ reference, value ]
      end.to_h
    end

    # WIQL is assembled from bound clauses; every value passes through the
    # escaper and the project predicate is added unconditionally.
    def build_wiql(filters, project_id)
      clauses = [ "[System.TeamProject] = @project" ]

      if (ids = Array(filters[:ids]).map(&:to_i).reject(&:zero?)).any?
        clauses << "[System.Id] IN (#{ids.join(', ')})"
      end
      clauses << "[System.WorkItemType] = '#{escape(filters[:type])}'" if filters[:type].present?
      clauses << "[System.State] = '#{escape(filters[:state])}'" if filters[:state].present?
      clauses << "[System.AssignedTo] = '#{escape(filters[:assigned_to])}'" if filters[:assigned_to].present?
      clauses << "[System.Title] CONTAINS '#{escape(filters[:title_contains])}'" if filters[:title_contains].present?
      clauses << "[System.Tags] CONTAINS '#{escape(filters[:tag])}'" if filters[:tag].present?
      clauses << "[System.State] NOT IN ('Closed', 'Removed', 'Done')" if filters[:open_only]

      # @project resolves to the project the request is scoped to, which is the
      # one in the URL path — so the predicate cannot be redirected by a filter.
      _ = project_id
      "SELECT [System.Id] FROM WorkItems WHERE #{clauses.join(' AND ')} ORDER BY [System.Id] DESC"
    end

    # WIQL string literals are single-quoted; doubling the quote is the escape.
    # Control characters are dropped rather than escaped — nothing legitimate
    # puts them in a work item filter.
    def escape(value)
      value.to_s.gsub(/[\x00-\x1f]/, "").gsub("'", "''").truncate(200, omission: "")
    end
  end
end
