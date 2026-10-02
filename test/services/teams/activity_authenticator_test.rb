# frozen_string_literal: true

require "test_helper"

class Teams::ActivityAuthenticatorTest < ActiveSupport::TestCase
  setup do
    with_teams_enabled
    stub_bot_framework_keys!
    @activity = teams_activity
  end

  def authenticate(token, activity = @activity)
    Teams::ActivityAuthenticator.authenticate!("Bearer #{token}", activity)
  end

  def refused(token, activity = @activity)
    assert_raises(Teams::ActivityAuthenticator::Unauthorized) { authenticate(token, activity) }.message
  end

  test "an activity the Bot Framework signed for this bot is accepted" do
    claims = authenticate(bot_framework_token)

    assert_equal TEAMS_APP_ID, claims["aud"]
  end

  test "each rule of Microsoft's checklist refuses on its own" do
    assert_equal "no bearer token", assert_raises(Teams::ActivityAuthenticator::Unauthorized) {
      Teams::ActivityAuthenticator.authenticate!(nil, @activity)
    }.message
    assert_equal "unknown signing key", refused(bot_framework_token(kid: "someone-else"))
    assert_match(/aud/i, refused(bot_framework_token(aud: "another-bot")))
    assert_match(/iss/i, refused(bot_framework_token(iss: "https://evil.example")))
    assert_match(/expired/i, refused(bot_framework_token(expires_at: 10.minutes.ago)))
    assert_equal "serviceUrl does not match the token", refused(bot_framework_token(service_url: "https://smba.trafficmanager.net/other/"))
  end

  test "a reply address outside the Bot Framework is refused even when the token names it" do
    forged = "https://attacker.example/"

    assert_equal "serviceUrl is not a Bot Framework host",
                 refused(bot_framework_token(service_url: forged), @activity.merge("serviceUrl" => forged))
  end

  test "a key not endorsed for Teams is refused" do
    stub_bot_framework_keys!(endorsements: [ "webchat" ])

    assert_equal "key not endorsed for msteams", refused(bot_framework_token)
  end

  test "a token signed with another key is refused" do
    other = OpenSSL::PKey::RSA.new(2048)
    token = JWT.encode({ iss: "https://api.botframework.com", aud: TEAMS_APP_ID, serviceurl: TEAMS_SERVICE_URL,
                         exp: 10.minutes.from_now.to_i }, other, "RS256", { kid: TEAMS_SIGNING_KID })

    assert_match(/signature/i, refused(token))
  end
end
