# frozen_string_literal: true

require "test_helper"

class ProjectTrackerTest < ActiveSupport::TestCase
  setup do
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
  end

  test "a tracker names an external project its connection covers, in the connection's own project" do
    tracker = build(:project_tracker, integration: @integration)
    assert tracker.valid?, tracker.errors.full_messages.to_sentence
    assert_equal "azure_devops", tracker.provider

    uncovered = build(:project_tracker, integration: @integration, external_scope_id: SecureRandom.uuid)
    refute_predicate uncovered, :valid?
    assert_includes uncovered.errors[:external_scope_id], "is not covered by this connection"

    owner = create(:user, company: @project.company)
    elsewhere = build(:project_tracker, integration: @integration, project: create(:project, company: @project.company, owner: owner))
    refute_predicate elsewhere, :valid?
    assert_includes elsewhere.errors[:integration], "is not available to this project"
  end

  test "handles are unique per project and look like handles" do
    create(:project_tracker, integration: @integration, handle: "boards")

    refute_predicate build(:project_tracker, integration: @integration, handle: "Boards!"), :valid?
    duplicate = build(:project_tracker, integration: @integration, handle: "boards", external_scope_id: "x")
    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:handle], "has already been taken"
  end

  test "handle_for suggests a free handle from a display name" do
    assert_equal "customer-platform", ProjectTracker.handle_for("Customer Platform")
    assert_equal "customer-platform-2", ProjectTracker.handle_for("Customer Platform", taken: %w[customer-platform])
    assert_equal "tracker", ProjectTracker.handle_for("Проект")
  end

  test "one primary per project, and a detached tracker gives it up" do
    first = create(:project_tracker, :primary, integration: @integration, handle: "first")
    extra = SecureRandom.uuid
    @integration.azure_devops_installation.update!(allowed_project_ids: @integration.azure_project_ids + [ extra ])
    @integration.update!(settings: @integration.settings.merge("azure_project_ids" => @integration.azure_project_ids + [ extra ]))
    second = create(:project_tracker, integration: @integration, external_scope_id: extra, handle: "second")

    second.make_primary!
    refute first.reload.primary
    assert second.reload.primary

    second.detach!
    assert_equal [ false, "detached" ], [ second.reload.primary, second.status ]
    refute_includes ProjectTracker.usable, second
  end

  # Production, 2026-10-02: a project's only tracker was detached and attached
  # again, and stayed without a primary.
  test "attaching a tracker again makes it primary, unless another tracker took that meanwhile" do
    only = create(:project_tracker, :primary, integration: @integration, handle: "only")

    only.detach!
    only.reattach!
    assert_equal [ true, "active" ], [ only.reload.primary, only.status ]

    extra = SecureRandom.uuid
    @integration.azure_devops_installation.update!(allowed_project_ids: @integration.azure_project_ids + [ extra ])
    @integration.update!(settings: @integration.settings.merge("azure_project_ids" => @integration.azure_project_ids + [ extra ]))
    other = create(:project_tracker, integration: @integration, external_scope_id: extra, handle: "other")
    only.detach!
    other.make_primary!
    only.reattach!
    assert_equal [ false, true ], [ only.reload.primary, other.reload.primary ]
  end

  test "mentions are recognised once the connection knows its own account in the tracker" do
    azure = create(:project_tracker, integration: @integration)
    refute_predicate azure, :recognizes_mentions?
    @integration.update!(settings: @integration.settings.merge("tracker_identity" => { "id" => "me-1", "name" => "Aixle" }))
    assert_predicate azure.reload, :recognizes_mentions?

    service_account = create(:integration, :jira, :active)
    assert_predicate create(:project_tracker, integration: service_account, external_scope_id: "10000"), :recognizes_mentions?
    person = create(:integration, :jira_oauth, :active)
    refute_predicate create(:project_tracker, integration: person, external_scope_id: "10000"), :recognizes_mentions?
  end

  test "a tracker is usable only while it is active and its connection is active" do
    tracker = create(:project_tracker, integration: @integration)
    assert tracker.usable?

    @integration.update!(status: :error)
    refute_predicate tracker.reload, :usable?
    refute_includes ProjectTracker.usable, tracker
  end
end
