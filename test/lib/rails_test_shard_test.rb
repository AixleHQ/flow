# frozen_string_literal: true

require "test_helper"
require "open3"

class RailsTestShardTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/rails-test-shard").to_s

  test "the shards together run every file a bare rails test runs, each exactly once" do
    shards = (1..3).map { |shard| list(shard, 3) }

    suite = Dir.glob("test/**/*_test.rb", base: Rails.root) -
      Dir.glob("test/{system,dummy,fixtures}/**/*_test.rb", base: Rails.root)

    assert_equal suite, shards.flatten.sort
    assert shards.all?(&:any?)
  end

  test "a shard outside the total is refused rather than run as the whole suite" do
    _out, err, status = Open3.capture3(SCRIPT, "4", "3", "--list")

    assert_equal 2, status.exitstatus
    assert_match(/out of range/, err)
  end

  private

  def list(shard, total)
    out, err, status = Open3.capture3(SCRIPT, shard.to_s, total.to_s, "--list")
    assert status.success?, err
    out.split("\n")
  end
end
