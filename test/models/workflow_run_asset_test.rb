# frozen_string_literal: true

require "test_helper"

class WorkflowRunAssetTest < ActiveSupport::TestCase
  test "name accepts a nested relative path" do
    asset = build(:workflow_run_asset, name: "reports/summary.md")

    assert asset.valid?, asset.errors.full_messages.to_sentence
  end

  test "name rejects a path that could leave the assets directory" do
    [ "../x", "/etc/passwd", "a/../../b", "back\\slash" ].each do |name|
      asset = build(:workflow_run_asset, name: name)

      assert_not asset.valid?, "#{name.inspect} should be invalid"
      assert_includes asset.errors[:name], Asset::NAME_MESSAGE
    end
  end
end
