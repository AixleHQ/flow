# frozen_string_literal: true

require "test_helper"

module Webhooks
  class SignatureVerifierTest < ActiveSupport::TestCase
    FakeRequest = Struct.new(:headers)

    def fake_request(headers = {})
      FakeRequest.new(headers)
    end

    # == slack_v0 ==

    test "slack_v0 accepts a correctly signed, fresh request" do
      secret = "slack-signing-secret"
      raw = '{"type":"event_callback"}'
      ts = Time.current.to_i.to_s
      sig = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "v0:#{ts}:#{raw}")}"
      req = fake_request("X-Slack-Request-Timestamp" => ts, "X-Slack-Signature" => sig)

      result = SignatureVerifier.verify(strategy: :slack_v0, secret: secret, request: req, raw_body: raw)

      assert result.ok?, result.reason
    end

    test "slack_v0 rejects a tampered body" do
      secret = "slack-signing-secret"
      ts = Time.current.to_i.to_s
      sig = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "v0:#{ts}:original")}"
      req = fake_request("X-Slack-Request-Timestamp" => ts, "X-Slack-Signature" => sig)

      result = SignatureVerifier.verify(strategy: :slack_v0, secret: secret, request: req, raw_body: "tampered")

      assert_not result.ok?
      assert_equal "signature mismatch", result.reason
    end

    test "slack_v0 rejects a stale timestamp (replay protection)" do
      secret = "slack-signing-secret"
      raw = "{}"
      ts = (Time.current.to_i - 10_000).to_s
      sig = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "v0:#{ts}:#{raw}")}"
      req = fake_request("X-Slack-Request-Timestamp" => ts, "X-Slack-Signature" => sig)

      result = SignatureVerifier.verify(strategy: :slack_v0, secret: secret, request: req, raw_body: raw)

      assert_not result.ok?
      assert_equal "stale timestamp", result.reason
    end

    # == hmac_sha256 ==

    test "hmac_sha256 accepts a valid sha256= signature" do
      secret = "hmac-secret"
      raw = '{"hello":"world"}'
      sig = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw)}"
      req = fake_request("X-Hub-Signature-256" => sig)

      result = SignatureVerifier.verify(strategy: :hmac_sha256, secret: secret, request: req, raw_body: raw)

      assert result.ok?, result.reason
    end

    test "hmac_sha256 rejects an invalid signature" do
      req = fake_request("X-Hub-Signature-256" => "sha256=deadbeef")

      result = SignatureVerifier.verify(strategy: :hmac_sha256, secret: "s", request: req, raw_body: "x")

      assert_not result.ok?
    end

    # == shared_token ==

    test "shared_token accepts a matching token" do
      req = fake_request("X-Webhook-Token" => "tok-123")
      result = SignatureVerifier.verify(strategy: :shared_token, secret: "tok-123", request: req, raw_body: "")
      assert result.ok?
    end

    test "shared_token rejects a mismatching token" do
      req = fake_request("X-Webhook-Token" => "wrong")
      result = SignatureVerifier.verify(strategy: :shared_token, secret: "tok-123", request: req, raw_body: "")
      assert_not result.ok?
    end

    # == none / unknown ==

    test "none strategy always passes" do
      result = SignatureVerifier.verify(strategy: :none, secret: nil, request: fake_request, raw_body: "anything")
      assert result.ok?
    end

    test "unknown strategy fails closed" do
      result = SignatureVerifier.verify(strategy: :nonsense, secret: "x", request: fake_request, raw_body: "")
      assert_not result.ok?
    end
  end
end
