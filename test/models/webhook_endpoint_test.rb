# frozen_string_literal: true

require "test_helper"

class WebhookEndpointTest < ActiveSupport::TestCase
  test "secret is stored encrypted and round-trips" do
    endpoint = create(:webhook_endpoint, secret: "super-secret")

    assert_not_nil endpoint.encrypted_secret
    assert_not_equal "super-secret", endpoint.encrypted_secret
    assert_equal "super-secret", endpoint.reload.secret
  end

  test "blank secret stores nil" do
    endpoint = create(:webhook_endpoint, :generic, secret: nil)
    assert_nil endpoint.secret
  end

  test "slug must be unique" do
    create(:webhook_endpoint, slug: "dup-slug")
    dup = build(:webhook_endpoint, slug: "dup-slug")
    assert_not dup.valid?
    assert_includes dup.errors[:slug], "has already been taken"
  end

  test "provider and verification_strategy are enumerized" do
    endpoint = build(:webhook_endpoint, provider: :slack, verification_strategy: :slack_v0)
    assert endpoint.slack?
    assert endpoint.valid?
  end
end
