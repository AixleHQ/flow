# frozen_string_literal: true

require "test_helper"

# Unit test for Oauth::State — the signed, short-lived, single-use OAuth `state`.
#
# This is the security core of the unified OAuth flow: it must (a) round-trip only
# non-secret routing data through a SIGNED payload, (b) keep the PKCE code_verifier
# server-side (never in the signed state), (c) reject tampered/expired states, and
# (d) enforce single use so a replayed authorization link cannot exchange a code.
#
# The nonce side-data lives in Rails.cache; the test env is :null_store (writes are
# no-ops, reads return nil), which would make every link look replayed — so we stub
# a live MemoryStore, exactly as the Slack OAuth test does.
class Oauth::StateTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
  end

  def encode(**overrides)
    Oauth::State.encode(**{
      owner_type: "Company",
      owner_id: 42,
      user_id: 7,
      provider: "sentry",
      return_to: "/company/projects/1",
      code_verifier: "pkce-verifier-abc123",
      mcp_server_id: nil
    }.merge(overrides))
  end

  test "encode returns a signed string whose decoded payload carries the routing data" do
    state = encode
    assert_kind_of String, state

    payload = Oauth::State.decode(state)
    assert_equal "Company", payload["owner_type"]
    assert_equal 42, payload["owner_id"]
    assert_equal 7, payload["user_id"]
    assert_equal "sentry", payload["provider"]
    assert_equal "/company/projects/1", payload["return_to"]
    assert payload["nonce"].present?, "a nonce must be embedded for single-use tracking"
  end

  test "the PKCE code_verifier is NEVER present in the signed state payload" do
    state = encode(code_verifier: "top-secret-verifier")
    payload = Oauth::State.decode(state)

    assert_nil payload["code_verifier"], "code_verifier must stay server-side, never in the URL"
    refute_includes state, "top-secret-verifier", "verifier must not be recoverable from the signed blob"
  end

  test "consume returns the cached code_verifier and user_id the first time" do
    state = encode(code_verifier: "verifier-xyz", user_id: 99)
    nonce = Oauth::State.decode(state)["nonce"]

    data = Oauth::State.consume(nonce)
    assert_equal "verifier-xyz", data["code_verifier"]
    assert_equal 99, data["user_id"]
  end

  test "consume is single-use: a replayed nonce returns nil (replay rejected)" do
    state = encode
    nonce = Oauth::State.decode(state)["nonce"]

    assert Oauth::State.consume(nonce), "first consume succeeds"
    assert_nil Oauth::State.consume(nonce), "second consume of the same nonce must be rejected"
  end

  test "consume returns nil for a blank nonce" do
    assert_nil Oauth::State.consume(nil)
    assert_nil Oauth::State.consume("")
  end

  test "consume returns nil for an unknown nonce" do
    assert_nil Oauth::State.consume(SecureRandom.uuid)
  end

  test "decode returns nil for a tampered / garbage state (bad signature)" do
    assert_nil Oauth::State.decode("not-a-real-state")
    assert_nil Oauth::State.decode(nil)

    tampered = "#{encode}x"
    assert_nil Oauth::State.decode(tampered)
  end

  test "decode returns nil once the state has expired past the TTL" do
    state = encode

    travel(Oauth::State::TTL + 1.minute) do
      assert_nil Oauth::State.decode(state), "an expired state must not verify"
    end
  end

  test "decode does NOT consume the nonce (cancel/error branch can still retry)" do
    state = encode
    nonce = Oauth::State.decode(state)["nonce"]
    # Decoding again and again leaves the single-use side-data intact.
    assert Oauth::State.decode(state)
    assert Oauth::State.consume(nonce), "nonce survives repeated decode calls"
  end
end
