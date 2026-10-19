# frozen_string_literal: true

require "test_helper"

# The admin edits a company's settings as JSON text. Assigned as text, a jsonb
# column stores a JSON string: the document became a string of itself on the
# first save, and every later save quoted it again.
class Admin::CompanySettingsJsonTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    sign_in_as(create(:user, :super_admin, :onboarding_completed, company: create(:company),
                                                                  password: AuthHelper::TEST_PASSWORD))
  end

  def save_settings(text)
    patch admin_company_path(@company), params: {
      company: { name: @company.name, email_domain: @company.email_domain, settings: text }
    }
  end

  # What the edit form shows in the editor, which is what a save sends back.
  def editor_text
    get edit_admin_company_path(@company)
    Nokogiri::HTML(response.body).at_css("textarea[name='company[settings]']").text
  end

  test "the editor's text is stored as the document it describes" do
    save_settings('{"features": {"sessions": true}}')

    assert_equal({ "features" => { "sessions" => true } }, @company.reload.settings)
  end

  test "saving the form unchanged, again and again, leaves the settings as they were" do
    @company.update!(settings: { "billing" => { "enabled" => false } })

    3.times { save_settings(editor_text) }

    assert_equal({ "billing" => { "enabled" => false } }, @company.reload.settings)
  end

  # An empty object is shown as `null`; sent back, it is the column's default.
  test "an empty editor is the default, not a string" do
    3.times { save_settings(editor_text) }

    assert_equal({}, @company.reload.settings)
  end

  test "text that is not JSON leaves the settings as they were" do
    @company.update!(settings: { "keep" => 1 })

    save_settings("{not json")

    assert_equal({ "keep" => 1 }, @company.reload.settings)
    assert_equal "Settings was not valid JSON and was left as it was.", flash[:alert]
  end
end
