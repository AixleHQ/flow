# frozen_string_literal: true

require "test_helper"

class IdentityProviderTest < ActiveSupport::TestCase
  test "deployment! is idempotent, so every environment provisions identically" do
    first = IdentityProvider.deployment!("password")
    second = IdentityProvider.deployment!("password")

    assert_equal first, second
    assert_equal 1, IdentityProvider.deployment_scoped.where(kind: "password").count
  end

  test "a deployment-scoped provider must not name a company" do
    provider = IdentityProvider.new(kind: "google", scope: "deployment", company: create(:company))

    provider.validate

    assert_includes provider.errors[:company], "must be blank for a deployment-scoped provider"
  end

  test "a company-scoped provider must name one" do
    provider = IdentityProvider.new(kind: "oidc", scope: "company")

    provider.validate

    assert_includes provider.errors[:company], "is required for a company-scoped provider"
  end

  test "an issuer on an internal or plain-http address is refused" do
    %w[http://169.254.169.254 http://10.0.0.1 https://10.0.0.1 https://127.0.0.1 https://localhost].each do |issuer|
      provider = build(:identity_provider, config: { "issuer" => issuer })

      refute_predicate provider, :valid?, "#{issuer} should be refused"
      assert_predicate provider.errors[:issuer], :any?
    end
  end

  test "an issuer carrying a query or fragment is refused" do
    [ "https://93.184.215.14/?x=", "https://93.184.215.14/#frag" ].each do |issuer|
      provider = build(:identity_provider, config: { "issuer" => issuer })

      provider.validate

      assert_includes provider.errors[:issuer], "must not contain a query or fragment"
    end
  end

  test "a public https issuer is accepted" do
    provider = build(:identity_provider, company: create(:company), config: { "issuer" => "https://93.184.215.14/tenant" })

    assert_predicate provider, :valid?
  end

  test "the database refuses an inconsistent scope even when validations are skipped" do
    provider = IdentityProvider.new(kind: "oidc", scope: "company")

    assert_raises(ActiveRecord::StatementInvalid) { provider.save!(validate: false) }
  end

  test "a company cannot have two connections of one kind with the same name" do
    company = create(:company)
    create(:identity_provider, company: company, kind: "oidc", name: "Acme SSO")
    duplicate = build(:identity_provider, company: company, kind: "oidc", name: "Acme SSO")

    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "another company may reuse a connection name" do
    create(:identity_provider, company: create(:company), kind: "oidc", name: "Acme SSO")

    assert_predicate build(:identity_provider, company: create(:company), kind: "oidc", name: "Acme SSO"), :valid?
  end

  test "a connection name is stored without surrounding whitespace, so a padded copy is a duplicate" do
    company = create(:company)
    provider = create(:identity_provider, company: company, kind: "oidc", name: "  Acme SSO ")

    assert_equal "Acme SSO", provider.reload.name
    duplicate = build(:identity_provider, company: company, kind: "oidc", name: "Acme SSO ")
    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "unnamed connections do not collide, matching the unique index" do
    company = create(:company)
    create(:identity_provider, company: company, kind: "oidc", name: nil)

    assert_predicate build(:identity_provider, company: company, kind: "oidc", name: nil), :valid?
  end

  test "the database refuses a duplicate connection name even when validations are skipped" do
    company = create(:company)
    create(:identity_provider, company: company, kind: "oidc", name: "Acme SSO")
    duplicate = build(:identity_provider, company: company, kind: "oidc", name: "Acme SSO")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "destroying a company takes its connections and policies with it" do
    company = create(:company)
    connection = create(:identity_provider, company: company, kind: "oidc")
    policy_count = CompanyAuthPolicy.where(company: company).count

    assert_operator policy_count, :>, 0, "a new company should have seeded policy rows"

    assert_difference "CompanyAuthPolicy.count", -policy_count do
      assert_difference "IdentityProvider.count", -1 do
        company.destroy!
      end
    end

    refute IdentityProvider.exists?(connection.id)
  end
end
