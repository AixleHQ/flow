# frozen_string_literal: true

require "test_helper"

class Activities::Coder::ReapDeadWorkspacesActivityTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user    = create(:user, :admin, company: @company)
  end

  test "returns the sweep totals" do
    totals = { integrations: 1, checked: 3, marked: 1, cleared: 1, deleted: 1, skipped: 0, errors: 0 }
    ::Coder::DeadWorkspaceReaper.expects(:reap_all).returns(totals)

    assert_equal totals, run_activity(Activities::Coder::ReapDeadWorkspacesActivity)
  end

  test "no-ops when no Coder integration is configured" do
    result = run_activity(Activities::Coder::ReapDeadWorkspacesActivity)

    assert_equal 0, result[:integrations]
    assert_equal 0, result[:deleted]
  end
end
