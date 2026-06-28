# frozen_string_literal: true

require "test_helper"

class IntegrationTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
  end

  # ====== Validations ======

  test "valid github integration" do
    integration = build(:integration, :github, :active, company: @company, connected_by: @user)
    assert { integration.valid? }
  end

  test "valid gitlab integration" do
    integration = build(:integration, :gitlab, :active, company: @company, connected_by: @user)
    assert { integration.valid? }
  end

  test "valid linear integration" do
    integration = build(:integration, :linear, company: @company, connected_by: @user)
    assert { integration.valid? }
  end

  test "valid coder integration" do
    integration = build(:integration, :coder, :active, company: @company, connected_by: @user)
    assert { integration.valid? }
  end

  test "coder integration round-trips coder_url and session_token through credentials" do
    integration = build(:integration, :coder, company: @company, connected_by: @user)
    integration.credentials_data = {
      coder_url: "https://coder.example.com",
      session_token: "vFVrbTLdls-XYZ"
    }
    integration.save!
    integration.reload

    assert_equal "https://coder.example.com", integration.credentials_data["coder_url"]
    assert_equal "vFVrbTLdls-XYZ", integration.credentials_data["session_token"]
    assert_equal "https://coder.example.com", integration.coder_url
  end

  test "coder integration encrypts session_token at rest" do
    integration = build(:integration, :coder, company: @company, connected_by: @user)
    integration.credentials_data = {
      coder_url: "https://coder.example.com",
      session_token: "vFVrbTLdls-XYZ"
    }
    integration.save!

    raw = integration.read_attribute(:credentials)
    assert { raw.present? }
    assert { !raw.include?("vFVrbTLdls-XYZ") }
    assert { !raw.include?("coder.example.com") }
  end

  test "coder_lock_ttl_minutes returns the stored setting" do
    integration = build(:integration, :coder, company: @company, connected_by: @user)
    integration.settings = { "lock_ttl_minutes" => 120 }
    assert_equal 120, integration.coder_lock_ttl_minutes
  end

  test "coder_lock_ttl_minutes returns nil when setting is absent" do
    integration = build(:integration, :coder, company: @company, connected_by: @user)
    integration.settings = {}
    assert_nil integration.coder_lock_ttl_minutes
  end

  test "IntegrationResource never serializes the session token" do
    integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
    integration.credentials_data = {
      coder_url: "https://coder.example.com",
      session_token: "vFVrbTLdls-SECRET-TOKEN-XYZ"
    }
    integration.save!

    serialized = IntegrationResource.new(integration).to_h
    json = serialized.to_json

    refute_includes json, "vFVrbTLdls-SECRET-TOKEN-XYZ"
    refute_includes json, "session_token"
    refute_includes json, "sessionToken"
    # Public Coder URL field is present (camelCased by Alba transform_keys :lower_camel).
    coder_url = serialized["coderUrl"] || serialized[:coderUrl] || serialized[:coder_url] || serialized["coder_url"]
    assert_equal "https://coder.example.com", coder_url
  end

  test "name must be present" do
    integration = build(:integration, name: nil, company: @company, connected_by: @user)
    assert { !integration.valid? }
    assert { integration.errors[:name].present? }
  end

  test "provider must be present" do
    integration = build(:integration, provider: nil, company: @company, connected_by: @user)
    assert { !integration.valid? }
    assert { integration.errors[:provider].present? }
  end

  test "allows multiple company-wide integrations with same provider per company" do
    create(:integration, :github, company: @company, connected_by: @user, name: "org-a", project_id: nil)
    second = build(:integration, :github, company: @company, connected_by: @user, name: "org-b", project_id: nil)
    assert { second.valid? }
    assert second.save!
  end

  test "find_or_build_github_for_installation returns existing row when installation_id matches" do
    first = create(:integration, :github, company: @company, connected_by: @user, name: "org-a", project_id: nil)
    first.update!(credentials_data: { "installation_id" => "111" })

    found = Integration.find_or_build_github_for_installation(
      company: @company,
      connected_by: @user,
      project: nil,
      installation_id: "111"
    )

    assert_equal first.id, found.id
  end

  test "find_or_build_github_for_installation builds new when installation_id unknown" do
    create(:integration, :github, company: @company, connected_by: @user, name: "org-a", project_id: nil)

    built = Integration.find_or_build_github_for_installation(
      company: @company,
      connected_by: @user,
      project: nil,
      installation_id: "999"
    )

    assert built.new_record?
    assert_equal @user, built.connected_by
  end

  # ====== Enumerize ======

  test "find_or_build_gitlab_for_token builds new integration" do
    built = Integration.find_or_build_gitlab_for_token(
      company: @company,
      connected_by: @user,
      project: nil
    )

    assert built.new_record?
    assert_equal :gitlab, built.provider.to_sym
    assert_equal @user, built.connected_by
    assert_equal @company, built.company
  end

  test "provider enumerize values" do
    assert_equal %w[github gitlab linear coder slack], Integration.provider.values.map(&:to_s)
  end

  test "status enumerize values" do
    assert_equal %w[active inactive error], Integration.status.values.map(&:to_s)
  end

  test "status defaults to inactive" do
    integration = Integration.new
    assert_equal "inactive", integration.status
  end

  # ====== Encryption ======

  test "credentials_data encrypts and decrypts hash" do
    integration = build(:integration, company: @company, connected_by: @user)
    data = { "installation_id" => "12345", "extra" => "value" }
    integration.credentials_data = data
    integration.save!
    integration.reload

    assert_equal data, integration.credentials_data
  end

  test "credentials column stores encrypted text not plain JSON" do
    integration = build(:integration, company: @company, connected_by: @user)
    integration.credentials_data = { "installation_id" => "12345" }
    integration.save!

    raw = integration.read_attribute(:credentials)
    assert { raw.present? }
    assert { raw != '{"installation_id":"12345"}' }
  end

  test "credentials_data returns empty hash when credentials blank" do
    integration = Integration.new
    assert_equal({}, integration.credentials_data)
  end

  test "credentials_data returns empty hash on invalid encrypted data" do
    integration = build(:integration, company: @company, connected_by: @user)
    integration[:credentials] = "garbage-data"
    assert_equal({}, integration.credentials_data)
  end

  test "installation_id convenience method" do
    integration = build(:integration, company: @company, connected_by: @user)
    integration.credentials_data = { "installation_id" => "67890" }
    assert_equal "67890", integration.installation_id
  end

  # ====== Scopes ======

  test "for_company scope" do
    other_company = create(:company)
    create(:integration, company: @company, connected_by: @user, name: "mine")
    create(:integration, company: other_company, connected_by: @user, name: "other")

    results = Integration.for_company(@company)
    assert_equal 1, results.count
    assert_equal "mine", results.first.name
  end

  test "active scope" do
    create(:integration, :active, company: @company, connected_by: @user, name: "active-one")
    create(:integration, :error, company: @company, connected_by: @user, name: "error-one")

    results = Integration.active
    assert_equal 1, results.count
    assert_equal "active-one", results.first.name
  end

  # ====== Associations ======

  test "belongs to company" do
    integration = create(:integration, company: @company, connected_by: @user)
    assert_equal @company, integration.company
  end

  test "belongs to connected_by user" do
    integration = create(:integration, company: @company, connected_by: @user)
    assert_equal @user, integration.connected_by
  end

  test "destroying company destroys integrations" do
    other_company = create(:company)
    other_user = create(:user, :employee, company: other_company)
    external_user = create(:user, :employee, company: create(:company))
    create(:integration, company: other_company, connected_by: external_user)
    assert_difference("Integration.count", -1) do
      other_company.destroy
    end
  end
end
