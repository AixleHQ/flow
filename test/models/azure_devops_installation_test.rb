# frozen_string_literal: true

require "test_helper"

class AzureDevopsInstallationTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  test "approved_project? is an allowlist with no unrestricted state" do
    project_id = SecureRandom.uuid
    installation = create(:azure_devops_installation, company: @company, allowed_project_ids: [ project_id ])

    assert installation.approved_project?(project_id)
    refute installation.approved_project?(SecureRandom.uuid)

    # An empty list means NO projects — the case a "blank means everything"
    # fallback would turn into organization-wide access.
    installation.update!(allowed_project_ids: [])
    refute installation.approved_project?(project_id)
    refute installation.approved_project?(nil)
  end

  test "rejects approved project ids that are not GUIDs" do
    installation = build(:azure_devops_installation, company: @company, allowed_project_ids: [ "Customer Platform" ])

    refute_predicate installation, :valid?
    assert_includes installation.errors[:allowed_project_ids], "must be Azure project GUIDs"
  end

  test "rejects an organization slug that is not a valid Azure organization name" do
    installation = build(:azure_devops_installation, company: @company, organization_slug: "contoso/../evil")

    refute_predicate installation, :valid?
    assert_includes installation.errors[:organization_slug], "is not a valid Azure organization name"
  end

  test "ownership and Azure identity cannot change once the row exists" do
    installation = create(:azure_devops_installation, :active, company: @company)
    other_company = create(:company)

    installation.company = other_company
    installation.tenant_id = SecureRandom.uuid
    refute_predicate installation, :valid?
    assert_includes installation.errors[:company_id], "cannot change on an existing installation"
    assert_includes installation.errors[:tenant_id], "cannot change on an existing installation"
  end

  test "verified identity may be set once and never rewritten" do
    installation = create(:azure_devops_installation, company: @company)

    installation.organization_id = SecureRandom.uuid
    assert installation.valid?, installation.errors.full_messages.to_sentence
    installation.save!

    installation.organization_id = SecureRandom.uuid
    refute_predicate installation, :valid?
    assert_includes installation.errors[:organization_id], "is verified and cannot change"
  end

  test "the cached token is encrypted at rest and readable back" do
    installation = create(:azure_devops_installation, company: @company)
    installation.cached_access_token = "super-secret-token"
    installation.save!

    assert_equal "super-secret-token", installation.reload.cached_access_token
    refute_includes installation.encrypted_access_token.to_s, "super-secret-token"
  end

  test "a cached token is only usable for the generation and resource it was minted under" do
    installation = create(:azure_devops_installation, company: @company)
    installation.cached_access_token = "token"
    installation.update!(
      token_expires_at: 1.hour.from_now,
      token_credential_generation: "v1",
      token_resource: "https://app.vssps.visualstudio.com/.default"
    )

    assert installation.token_usable?(generation: "v1", resource: "https://app.vssps.visualstudio.com/.default")
    refute installation.token_usable?(generation: "v2", resource: "https://app.vssps.visualstudio.com/.default")
    refute installation.token_usable?(generation: "v1", resource: "https://other.resource/.default")
    # Inside the safety window counts as spent, which is the case a bare
    # "expires_at is in the future" check gets wrong.
    refute installation.token_usable?(generation: "v1",
                                      resource: "https://app.vssps.visualstudio.com/.default",
                                      skew: 2.hours)
  end

  test "clear_token_cache! removes the value and its provenance together" do
    installation = create(:azure_devops_installation, company: @company)
    installation.cached_access_token = "token"
    installation.update!(token_expires_at: 1.hour.from_now, token_credential_generation: "v1", token_resource: "r")

    installation.clear_token_cache!

    installation.reload
    assert_nil installation.cached_access_token
    assert_nil installation.token_expires_at
    assert_nil installation.token_credential_generation
  end

  test "an installation with project integrations cannot be destroyed" do
    integration = create(:integration, :azure_devops, :active, company: @company)
    installation = integration.azure_devops_installation

    refute installation.destroy
    assert_includes installation.errors[:base].to_sentence, "integrations"
    assert AzureDevopsInstallation.exists?(installation.id)
  end
end
