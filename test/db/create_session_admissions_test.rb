# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260905120000_create_session_admissions")

# The migration is the only thing that runs on a Marketplace installation with
# nobody to run a task, so it is where the queue gets switched on — but only
# where switching it on is safe.
class CreateSessionAdmissionsTest < ActiveSupport::TestCase
  setup { @migration = CreateSessionAdmissions.new }

  test "an empty database is a fresh installation" do
    assert @migration.fresh_installation?
  end

  test "a database that has served a session is an upgrade, not a fresh install" do
    create(:terminal_session, user: create(:user, :with_company))

    assert_not @migration.fresh_installation?,
      "enabling here would queue sessions that are already running"
  end

  test "a database that has served a workflow run is an upgrade too" do
    create(:workflow_run)

    assert_not @migration.fresh_installation?
  end
end
