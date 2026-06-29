# frozen_string_literal: true

require "test_helper"

class IntegrationDataTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
  end

  test "round-trips a jsonb payload" do
    row = create(
      :integration_data, :future_expiry,
      integration: @integration,
      key:         "coder:workspace_lock:foo",
      value:       { kind: "workspace_lock", terminal_session_id: "abc" }
    )

    reloaded = IntegrationData.find(row.id)
    assert_equal "workspace_lock", reloaded.value["kind"]
    assert_equal "abc", reloaded.value["terminal_session_id"]
  end

  test "live scope returns rows with no expiry or future expiry" do
    no_expiry = create(:integration_data, integration: @integration, key: "k1")
    future    = create(:integration_data, :future_expiry, integration: @integration, key: "k2")
    past      = create(:integration_data, :expired, integration: @integration, key: "k3")

    assert_includes IntegrationData.live, no_expiry
    assert_includes IntegrationData.live, future
    assert_not_includes IntegrationData.live, past
  end

  test "expired scope returns only past-expiry rows" do
    no_expiry = create(:integration_data, integration: @integration, key: "k1")
    future    = create(:integration_data, :future_expiry, integration: @integration, key: "k2")
    past      = create(:integration_data, :expired, integration: @integration, key: "k3")

    assert_not_includes IntegrationData.expired, no_expiry
    assert_not_includes IntegrationData.expired, future
    assert_includes     IntegrationData.expired, past
  end

  test "with_key_prefix scope filters rows by key prefix" do
    matching = create(:integration_data, integration: @integration, key: "coder:workspace_lock:foo")
    other    = create(:integration_data, integration: @integration, key: "other:thing:bar")

    scoped = IntegrationData.with_key_prefix("coder:workspace_lock:")

    assert_includes     scoped, matching
    assert_not_includes scoped, other
  end

  test "with_key_prefix escapes LIKE wildcards in the prefix" do
    literal = create(:integration_data, integration: @integration, key: "literal%key:1")
    other   = create(:integration_data, integration: @integration, key: "literalXkey:1")

    scoped = IntegrationData.with_key_prefix("literal%")

    assert_includes     scoped, literal
    assert_not_includes scoped, other
  end

  test "uniqueness on (integration_id, key) is enforced at the DB level" do
    create(:integration_data, integration: @integration, key: "coder:workspace_lock:foo")

    assert_raises ActiveRecord::RecordNotUnique do
      create(:integration_data, integration: @integration, key: "coder:workspace_lock:foo")
    end
  end

  test "same key across two integrations is allowed" do
    other = create(:integration, :coder, :active, company: @company, connected_by: @user)
    create(:integration_data, integration: @integration, key: "coder:workspace_lock:foo")

    assert_nothing_raised do
      create(:integration_data, integration: other, key: "coder:workspace_lock:foo")
    end
  end

  test "destroying integration deletes integration_data rows (FK cascade)" do
    create(:integration_data, integration: @integration, key: "k1")
    create(:integration_data, integration: @integration, key: "k2")

    assert_difference "IntegrationData.count", -2 do
      @integration.destroy
    end
  end
end
