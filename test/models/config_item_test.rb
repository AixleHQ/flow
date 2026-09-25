# frozen_string_literal: true

require "test_helper"

class ConfigItemTest < ActiveSupport::TestCase
  setup do
    @project = create(:project, :standalone)
  end

  def stored(item)
    ConfigItem.connection.select_one("SELECT value, encrypted_value FROM config_items WHERE id = #{item.id}")
  end

  test "a secret is stored encrypted, never as plaintext" do
    item = create(:config_item, scope: @project, name: "API_KEY", item_type: :secret, value: "sk-live-123")

    row = stored(item)
    assert_nil row["value"]
    assert_not_includes row["encrypted_value"], "sk-live-123"
    assert_equal "sk-live-123", item.reload.decrypted_value
  end

  # The edit form submits the field empty to mean "keep".
  test "an update with a blank value keeps the stored one" do
    variable = create(:config_item, scope: @project, name: "REGION", value: "eu-west-1")
    secret = create(:config_item, scope: @project, name: "TOKEN", item_type: :secret, value: "t-123")

    variable.update!(value: "", description: "renamed")
    secret.update!(value: "")

    assert_equal "eu-west-1", variable.reload.value
    assert_equal "t-123", secret.reload.decrypted_value
  end

  test "turning a variable into a secret encrypts the value it already has" do
    item = create(:config_item, scope: @project, name: "DB_PASSWORD", value: "hunter2")

    item.update!(item_type: :secret)

    assert_nil stored(item)["value"]
    assert_equal "hunter2", item.reload.decrypted_value
  end

  test "turning a secret into a variable needs its value typed again" do
    item = create(:config_item, scope: @project, name: "DB_PASSWORD", item_type: :secret, value: "hunter2")

    assert_not item.update(item_type: :variable)
    assert_includes item.errors[:value], "must be entered again to turn a secret into a variable"

    assert item.reload.update(item_type: :variable, value: "now-visible")
    assert_equal "now-visible", item.reload.value
  end
end
