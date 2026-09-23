# frozen_string_literal: true

require "test_helper"

class Web::Company::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  def limit_for(company) = SessionConcurrencyLimit.find_by(scope_type: "Company", scope_id: company.id)

  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  def self_hosted! = with_mode(Deployment::SELF_HOSTED)
  def saas! = with_mode(Deployment::SAAS)
  def marketplace! = with_mode(Deployment::AWS_MARKETPLACE)

  test "show renders the settings page" do
    get company_settings_path

    assert_inertia_page "Company/Settings/SettingsPage"
  end

  test "show reports the company's capacity and how its projects spent it" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 20)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 6)

    get company_settings_path

    assert_inertia_props do |props|
      assert_equal 20, props[:capacity][:maxSessions]
      assert_equal 6, props[:capacity][:reserved]
      assert_equal 14, props[:capacity][:available]
      assert_equal [ @project.name ], props[:capacity][:allocations].map { |a| a[:name] }
    end
  end

  test "an admin updates the company's branding" do
    patch company_settings_path, params: { company: { display_name: "Acme Robotics" } }

    assert_response :redirect
    assert_equal "Acme Robotics", @company.reload.display_name
  end

  # == logo ==

  def png_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/logo.png"), "image/png"
    )
  end

  test "an admin uploads a logo" do
    patch company_settings_path, params: { company: { display_name: "Acme", logo: png_upload } }

    assert_response :redirect
    assert @company.reload.logo.present?, "the attachment must survive the save"
  end

  # Shrine's remove_attachment plugin is not loaded, so clearing is our own flag.
  test "an admin removes the logo" do
    patch company_settings_path, params: { company: { display_name: "Acme", logo: png_upload } }
    assert @company.reload.logo.present?

    patch company_settings_path, params: { company: { display_name: "Acme", remove_logo: "true" } }

    assert_nil @company.reload.logo
  end

  test "a save that does not mention the logo leaves it alone" do
    patch company_settings_path, params: { company: { display_name: "Acme", logo: png_upload } }

    patch company_settings_path, params: { company: { display_name: "Renamed" } }

    assert @company.reload.logo.present?
  end

  # MIME comes from the bytes, not the client's Content-Type, so a mislabelled
  # upload is refused rather than stored.
  test "a file that is not an image is refused" do
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/not-an-image.txt"), "image/png"
    )

    patch company_settings_path, params: { company: { display_name: "Acme", logo: file } }

    assert_nil @company.reload.logo
    assert_nil @company.display_name, "a refused logo must roll the rest of the save back"
  end

  # == session capacity ==

  # "Unlimited" has no encoding in a metering record, so where the installation
  # meters itself to AWS a company cannot be left without a number.
  test "a marketplace admin may not clear the limit" do
    marketplace!
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 12)

    patch company_settings_path, params: { company: { display_name: "Acme" }, capacity: "" }

    assert_equal 12, limit_for(@company)&.max_sessions
    assert_match(/AWS Marketplace/, Array(session["inertia_errors"][:capacity]).to_sentence)
  end

  test "a marketplace admin may still change the limit" do
    marketplace!

    patch company_settings_path, params: { company: { display_name: "Acme" }, capacity: "30" }

    assert_equal 30, limit_for(@company)&.max_sessions
  end

  # Every other path that clears a limit is stopped in the model, so the console
  # and the admin form are covered by the same rule as the form above.
  test "the row itself refuses to be destroyed in marketplace mode" do
    marketplace!
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 12)
    row = SessionConcurrencyLimit.find_by(scope_type: "Company", scope_id: @company.id)

    assert_not row.destroy

    assert_equal 12, limit_for(@company)&.max_sessions
  end


  test "a self-hosted admin sets the company's session limit" do
    self_hosted!

    patch company_settings_path, params: { company: { display_name: "Acme" }, capacity: "12" }

    assert_equal 12, limit_for(@company)&.max_sessions
  end

  test "clearing the field removes the limit rather than setting it to zero" do
    self_hosted!
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 12)

    patch company_settings_path, params: { company: { display_name: "Acme" }, capacity: "" }

    assert_nil limit_for(@company)
  end

  # The number the hosted product invoices for is not self-serve, whatever the
  # membership role: only a platform administrator moves it.
  test "a saas admin may not set the company's session limit" do
    saas!

    patch company_settings_path, params: { company: { display_name: "Acme" }, capacity: "12" }

    assert_nil limit_for(@company)
    assert_match(/installation's administrator/, Array(session["inertia_errors"][:capacity]).to_sentence)
  end

  test "a saas admin is told the limit is not theirs to move" do
    saas!

    get company_settings_path

    assert_inertia_props do |props|
      assert_equal false, props[:capacity][:canManage] # rubocop:disable Minitest/RefuteFalse
    end
  end

  test "a refused capacity rolls back the rest of the save" do
    self_hosted!

    patch company_settings_path, params: { company: { display_name: "Renamed" }, capacity: "0" }

    assert_nil @company.reload.display_name, "the name must not survive a refused save"
    assert_nil limit_for(@company)
  end

  # An update that does not submit the field must leave the limit alone, or
  # saving a logo would silently exempt the company from billing.
  test "an update without the field leaves the limit untouched" do
    self_hosted!
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 12)

    patch company_settings_path, params: { company: { display_name: "Acme" } }

    assert_equal 12, limit_for(@company)&.max_sessions
  end
end
