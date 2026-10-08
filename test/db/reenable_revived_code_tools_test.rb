# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261008090000_reenable_revived_code_tools")

class ReenableRevivedCodeToolsTest < ActiveSupport::TestCase
  def migrate
    migration = ReenableRevivedCodeTools.new
    migration.suppress_messages { migration.up }
  end

  test "a live code tool left disabled is enabled again; retired and custom tools are left as they are" do
    Tools::Reconciler.run!
    revived = Tool.code_source.find_by!(name: "chat_post_message")
    revived.update_columns(enabled: false)
    retired = Tool.code_source.find_by!(name: "board_get_task")
    retired.update_columns(deleted_at: Time.current, enabled: false)
    custom = create(:tool, enabled: false)

    migrate

    assert revived.reload.enabled?
    assert_not retired.reload.enabled?
    assert_not custom.reload.enabled?
  end
end
