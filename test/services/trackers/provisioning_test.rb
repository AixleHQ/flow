# frozen_string_literal: true

require "test_helper"

class Trackers::ProvisioningTest < ActiveSupport::TestCase
  setup do
    @integration = create(:integration, :azure_devops, :active)
    first = @integration.azure_project_ids.first
    @extra = SecureRandom.uuid
    @integration.azure_devops_installation.update!(allowed_project_ids: [ first, @extra ])
    @integration.update!(settings: @integration.settings.merge(
      "azure_project_ids" => [ first, @extra ], "azure_project_names" => { first => "Customer Platform", @extra => "Ops" }
    ))
  end

  test "every Azure project of the connection becomes a tracker, the first one primary" do
    Trackers::Provisioning.ensure_for!(@integration)

    trackers = ProjectTracker.for_project(@integration.project).order(:id)
    assert_equal %w[customer-platform ops], trackers.map(&:handle)
    assert_equal [ true, false ], trackers.map(&:primary)
  end

  test "it is idempotent and never brings back a tracker someone detached" do
    Trackers::Provisioning.ensure_for!(@integration)
    ProjectTracker.find_by!(external_scope_id: @extra).detach!

    Trackers::Provisioning.ensure_for!(@integration)

    assert_equal 2, ProjectTracker.for_project(@integration.project).count
    assert ProjectTracker.find_by!(external_scope_id: @extra).detached?
  end

  test "a project that already has a primary tracker keeps it" do
    create(:project_tracker, :primary, integration: @integration, external_scope_id: @extra, handle: "ops-board")

    Trackers::Provisioning.ensure_for!(@integration)

    assert_equal [ "ops-board" ], ProjectTracker.for_project(@integration.project).where(primary: true).pluck(:handle)
  end
end
