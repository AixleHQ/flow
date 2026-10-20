# frozen_string_literal: true

require "test_helper"

module Trackers
  module AzureDevops
    class ProviderTest < ActiveSupport::TestCase
      setup do
        with_azure_devops_enabled
        @integration = create(:integration, :azure_devops, :active)
        @scope = @integration.azure_project_ids.first
        @fakes = stub_azure_devops!(integration: @integration)
        @provider = Trackers::Provider.for(@integration)
      end

      test "maps a work item onto the tracker issue shape" do
        issue = @provider.get_issue(@scope, "11")

        assert_equal "11", issue.id
        assert_equal "Bug", issue.type
        assert_equal "Active", issue.status.name
        assert_equal [ "Ada" ], issue.assignees
        assert_equal @scope, issue.scope_id
        assert_equal @scope, @fakes.work_items.calls_to(:get).last[:project_id]
      end

      test "accepts a work item as #id or as its browser URL" do
        organization = @integration.azure_organization_slug
        @provider.get_issue(@scope, "https://dev.azure.com/#{organization}/Customer%20Platform/_workitems/edit/11")
        @provider.get_issue(@scope, "#11")

        assert_equal [ 11, 11 ], @fakes.work_items.calls_to(:get).pluck(:work_item_id)
      end

      test "refuses a reference that is not a work item" do
        error = assert_raises(Trackers::Error) { @provider.get_issue(@scope, "APP-12") }

        assert_equal "validation_failed", error.code
        assert_empty @fakes.work_items.calls_to(:get)
      end

      test "a URL owns its issue only for this organization and project" do
        organization = @integration.azure_organization_slug

        assert @provider.owns_reference?(@scope, "https://dev.azure.com/#{organization}/Customer%20Platform/_workitems/edit/11")
        refute @provider.owns_reference?(@scope, "https://dev.azure.com/#{organization}/Elsewhere/_workitems/edit/11")
        refute @provider.owns_reference?(@scope, "https://dev.azure.com/other-org/Customer%20Platform/_workitems/edit/11")
        refute @provider.owns_reference?(@scope, "11")
      end

      test "search translates the tracker filter into Azure's" do
        page = @provider.search_issues(@scope, { text: "breaks", status: "Active", labels: %w[ai urgent], open_only: true })

        assert_equal({ title_contains: "breaks", state: "Active", tag: "ai", open_only: true },
                     @fakes.work_items.calls_to(:query).last[:filters])
        assert_equal [ "11" ], page.items.map(&:id)
        refute_predicate page, :has_more?
      end

      test "a native query is refused rather than ignored" do
        error = assert_raises(Trackers::Error) { @provider.search_issues(@scope, { native_query: "SELECT *" }) }

        assert_equal "validation_failed", error.code
      end

      test "creating needs a type and passes labels as Azure tags" do
        error = assert_raises(Trackers::Error) { @provider.create_issue(@scope, { title: "x" }) }
        assert_equal "validation_failed", error.code

        @provider.create_issue(@scope, { type: "Bug", title: "It breaks", labels: %w[ai triage], fields: { "priority" => 2 } })

        create = @fakes.work_items.calls_to(:create).last
        assert_equal "Bug", create[:type]
        assert_equal({ title: "It breaks", tags: "ai; triage", priority: 2 }, create[:fields])
      end

      test "adding and removing labels rewrites Azure's tag set from the current one" do
        @fakes.work_items.instance_variable_set(:@work_item, FakeAzureDevops::WorkItemService::DEFAULT_ITEM.merge(tags: "old; keep"))

        @provider.update_issue(@scope, "11", { labels_add: [ "new" ], labels_remove: [ "OLD" ] })

        assert_equal({ tags: "keep; new" }, @fakes.work_items.calls_to(:update).last[:fields])
      end

      test "a transition must name a state of the issue's type, matched case-insensitively" do
        error = assert_raises(Trackers::Error) { @provider.transition_issue(@scope, "11", "Done") }
        assert_equal({ allowed: %w[Active Resolved] }, error.details)

        issue = @provider.transition_issue(@scope, "11", "resolved")

        assert_equal({ state: "Resolved" }, @fakes.work_items.calls_to(:update).last[:fields])
        assert_equal "Resolved", issue.status.name
      end

      test "describe reports the board's columns as statuses, and the states transitions set" do
        description = @provider.describe(@scope)

        assert_equal [ %w[New todo], [ "Ready for AI", "todo" ], %w[Active in_progress], %w[Closed done] ],
                     description[:statuses].map { |s| [ s.name, s.category ] }
        assert_equal [ %w[Active in_progress], %w[Resolved in_progress] ],
                     description[:states].map { |s| [ s.name, s.category ] }
        assert_equal "Bug", description[:issue_types].first[:name]
      end

      test "an issue's status is the column its card sits in, categorized by the state behind it" do
        @fakes.work_items.instance_variable_set(:@work_item,
                                                FakeAzureDevops::WorkItemService::DEFAULT_ITEM.merge(board_column: "Ready for AI"))

        issue = @provider.get_issue(@scope, "11")

        assert_equal [ "Ready for AI", "in_progress" ], [ issue.status.name, issue.status.category ]
        assert_equal({ "state" => "Active", "board_column" => "Ready for AI", "area_path" => "Customer Platform" }, issue.fields)
      end

      test "a column move is the status change; a state change alone counts only off the board" do
        on_board = Trackers::Issue.new(id: "11", key: "11", url: nil, title: "t", description: nil, type: "Bug",
                                       status: Trackers::Status.new(id: "Ready for AI", name: "Ready for AI", category: "in_progress"),
                                       assignees: [], labels: [], revision: 4, scope_id: @scope, updated_at: nil,
                                       fields: { "state" => "Active", "board_column" => "Ready for AI" })
        moved = @provider.status_change([ { field: "board_column", from: "New", to: "Ready for AI" },
                                          { field: "state", from: "New", to: "Active" } ], on_board)

        assert_equal [ "Ready for AI", "in_progress", { "from" => "New", "to" => "Active" } ],
                     [ moved.dig("to", "name"), moved.dig("to", "category"), moved["state"] ]
        assert_nil @provider.status_change([ { field: "state", from: "New", to: "Active" } ], on_board)

        off_board = on_board.with(fields: { "state" => "Active" })
        assert_equal "Active", @provider.status_change([ { field: "state", from: "New", to: "Active" } ], off_board).dig("to", "name")
      end

      test "a comment is read back through the issue, so its scope is checked first" do
        comment = @provider.add_comment(@scope, "11", "on it")

        assert_equal %i[get add_comment], @fakes.work_items.calls.map { |c| c[:method] }
        assert_equal "11", comment.issue_id
      end

      test "Azure errors come back as tracker errors with the same code" do
        @fakes.work_items.instance_variable_set(:@error, ::AzureDevops::NotFound.new("gone"))
        error = assert_raises(Trackers::Error) { @provider.get_issue(@scope, "11") }
        assert_equal "not_found_or_inaccessible", error.code

        @fakes.work_items.instance_variable_set(:@error, ::AzureDevops::OutcomeUnknown.new("no answer"))
        assert_raises(Trackers::Error::OutcomeUnknown) { @provider.add_comment(@scope, "11", "x") }
      end

      test "the connection serves only its own project and covers only its approved Azure projects" do
        assert @provider.serves_project?(@integration.project)
        company = @integration.company
        refute @provider.serves_project?(create(:project, company: company, owner: create(:user, company: company)))
        assert @provider.covers_scope?(@scope)
        refute @provider.covers_scope?(SecureRandom.uuid)
      end
      test "files include images embedded in the work item's HTML, and download by guid" do
        attached = @fakes.work_items.add_file(name: "trace.log", bytes: "trace")
        inline = @fakes.work_items.add_file(name: "steps.png", bytes: "png", origin: :embedded, location: { "kind" => "description" })
        io = StringIO.new

        files = @provider.list_attachments(@scope, "11")
        @provider.download_attachment(@scope, "11", inline.upcase, io: io, max_bytes: 1.megabyte)

        assert_equal [ [ attached, :attached ], [ inline, :embedded ] ], files.map { |f| [ f.id, f.origin ] }
        assert_equal "png", io.string
      end

      test "a retry after the link failed links the upload already made" do
        Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
        @fakes.work_items.fail_link = true
        file = -> { Trackers::UploadFile.new(io: StringIO.new("a"), filename: "a.txt", content_type: "text/plain", size: 1, sha256: "s1") }

        assert_raises(Trackers::Error) { @provider.upload_attachment(@scope, "11", file.call) }
        attachment = @provider.upload_attachment(@scope, "11", file.call)

        assert_equal [ false, true ], @fakes.work_items.calls_to(:upload_attachment).pluck(:reused_upload)
        assert_equal 1, @fakes.work_items.uploads.size
        assert_equal "a.txt", attachment.name
      end

      test "a comment shows files as HTML" do
        image = Trackers::Attachment.new(id: "g1", issue_id: "11", name: "a<b>.png", content_type: "image/png", url: "https://dev.azure.com/o/p/_apis/wit/attachments/g1?fileName=a.png")
        doc = Trackers::Attachment.new(id: "g2", issue_id: "11", name: "spec.pdf", url: "https://dev.azure.com/o/p/_apis/wit/attachments/g2?fileName=spec.pdf")

        assert_equal %(Done<br><br><img src="https://dev.azure.com/o/p/_apis/wit/attachments/g1?fileName=a.png" alt="a&lt;b&gt;.png">) +
                     %(<br><br><a href="https://dev.azure.com/o/p/_apis/wit/attachments/g2?fileName=spec.pdf">spec.pdf</a>),
                     @provider.compose_comment("Done", [ image, doc ])
      end
    end
  end
end
