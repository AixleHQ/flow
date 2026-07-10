# frozen_string_literal: true

require "test_helper"

class OauthClientTest < ActiveSupport::TestCase
  def valid_attrs(**overrides)
    {
      issuer: "https://sentry.io",
      authorization_endpoint: "https://sentry.io/oauth/authorize/",
      token_endpoint: "https://sentry.io/oauth/token/",
      client_id: "client-123",
      source: "static"
    }.merge(overrides)
  end

  # --- validations ---

  test "valid with required attributes" do
    assert OauthClient.new(valid_attrs).valid?
  end

  test "requires issuer, endpoints, client_id and source" do
    client = OauthClient.new
    assert_not client.valid?
    %i[issuer authorization_endpoint token_endpoint client_id source].each do |attr|
      assert_includes client.errors.attribute_names, attr
    end
  end

  test "client_id is unique within an issuer" do
    OauthClient.create!(valid_attrs)
    dup = OauthClient.new(valid_attrs)

    assert_not dup.valid?
    assert_includes dup.errors[:client_id], "has already been taken"
  end

  test "the same client_id is allowed for a different issuer" do
    OauthClient.create!(valid_attrs)
    other = OauthClient.new(valid_attrs(
                              issuer: "https://railway.app",
                              authorization_endpoint: "https://railway.app/oauth/authorize",
                              token_endpoint: "https://backboard.railway.app/oauth/token"
                            ))

    assert other.valid?
  end

  # --- encrypted client secret ---

  test "client_secret encrypts at rest and round-trips through decrypt" do
    client = OauthClient.create!(valid_attrs(client_secret: "s3cr3t"))

    assert_not_nil client.encrypted_client_secret
    assert_not_equal "s3cr3t", client.encrypted_client_secret
    assert_equal "s3cr3t", client.reload.client_secret
  end

  test "a blank client_secret stores nil and stays non-confidential" do
    client = OauthClient.create!(valid_attrs(client_secret: ""))

    assert_nil client.encrypted_client_secret
    assert_nil client.client_secret
    assert_not client.confidential?
  end

  test "confidential? is true once a secret is set" do
    assert OauthClient.create!(valid_attrs(client_secret: "s3cr3t")).confidential?
  end

  test "client_secret returns nil when the ciphertext is tampered" do
    client = OauthClient.create!(valid_attrs)
    client.update_column(:encrypted_client_secret, "not-a-valid-ciphertext")

    assert_nil client.reload.client_secret
  end

  # --- association ---

  test "destroying a client destroys its dependent credentials" do
    client = OauthClient.create!(valid_attrs)
    company = create(:company)
    client.oauth_credentials.create!(owner: company, provider: "sentry")

    assert_difference "OauthCredential.count", -1 do
      client.destroy
    end
  end
end
