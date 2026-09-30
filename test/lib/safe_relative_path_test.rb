# frozen_string_literal: true

require "test_helper"

class SafeRelativePathTest < ActiveSupport::TestCase
  test "join places a relative path under the root" do
    assert_equal "/workspace/assets/docs/spec.md", SafeRelativePath.join("/workspace/assets", "docs/spec.md")
  end

  test "join refuses anything that would land outside the root" do
    [ "../x", "a/../../x", "/etc/passwd", "~root/.ssh/authorized_keys", "", nil, "a\\..\\x", "nul\0byte" ].each do |path|
      assert_nil SafeRelativePath.join("/workspace/assets", path), "#{path.inspect} should be refused"
    end
  end
end
