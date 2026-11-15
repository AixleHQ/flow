# frozen_string_literal: true

require "test_helper"

class SubStepRunTest < ActiveSupport::TestCase
  test "done? is true for completed and skipped, not for pending or in progress" do
    %w[completed skipped].each do |state|
      assert SubStepRun.new(state: state).done?, state
    end
    %w[pending in_progress].each do |state|
      assert_not SubStepRun.new(state: state).done?, state
    end
  end
end
