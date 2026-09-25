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

  test "a trigger's endpoint demands a generated shared token unless told otherwise" do
    user = create(:user, :with_company)
    project = create(:project, company: user.companies.first, owner: user)

    endpoint = WebhookEndpoint.create_for_trigger!(project: project, created_by: user)

    assert_equal "shared_token", endpoint.verification_strategy
    assert_operator endpoint.secret.length, :>=, 32
    assert_match(/\Awh-\h{32}\z/, endpoint.slug)
    assert_equal "webhook.#{endpoint.slug.delete_prefix('wh-')}", endpoint.config["event_type"]
  end

  test "a trigger's endpoint keeps an explicit strategy and secret, and none carries no secret" do
    user = create(:user, :with_company)
    project = create(:project, company: user.companies.first, owner: user)

    hmac = WebhookEndpoint.create_for_trigger!(project: project, created_by: user,
                                               verification_strategy: "hmac_sha256", secret: "shh")
    open = WebhookEndpoint.create_for_trigger!(project: project, created_by: user, verification_strategy: "none")

    assert_equal [ "hmac_sha256", "shh" ], [ hmac.verification_strategy, hmac.secret ]
    assert_equal "none", open.verification_strategy
    assert_nil open.secret
  end
end
