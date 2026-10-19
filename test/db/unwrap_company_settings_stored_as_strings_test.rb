# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261019110000_unwrap_company_settings_stored_as_strings")

class UnwrapCompanySettingsStoredAsStringsTest < ActiveSupport::TestCase
  def migrate
    migration = UnwrapCompanySettingsStoredAsStrings.new
    migration.suppress_messages { migration.up }
  end

  test "settings saved as strings become the document they quote, or the default" do
    document = { "billing" => { "enabled" => false }, "features" => { "sessions" => true } }
    quoted_once = create(:company)
    quoted_once.update_columns(settings: document.to_json)
    quoted_twice = create(:company)
    quoted_twice.update_columns(settings: document.to_json.to_json)
    null = create(:company)
    null.update_columns(settings: "null")
    intact = create(:company)
    intact.update_columns(settings: { "keep" => 1 })

    migrate
    migrate

    assert_equal document, quoted_once.reload.settings
    assert_equal document, quoted_twice.reload.settings
    assert_equal({}, null.reload.settings)
    assert_equal({ "keep" => 1 }, intact.reload.settings)
  end
end
