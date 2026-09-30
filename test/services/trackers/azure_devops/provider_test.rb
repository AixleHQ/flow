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
        assert_equal @scope, @fakes.work_items.last_call[:project_id]
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
                     @fakes.work_items.last_call[:filters])
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

        create = @fakes.work_items.last_call
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

      test "describe reports statuses with portable categories" do
        description = @provider.describe(@scope)

        assert_equal [ %w[Active in_progress], %w[Resolved in_progress] ],
                     description[:statuses].map { |s| [ s.name, s.category ] }
        assert_equal "Bug", description[:issue_types].first[:name]
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
    end
  end
end
