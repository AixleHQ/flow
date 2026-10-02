# frozen_string_literal: true

# Teams in tests: a configured bot, Entra's token endpoint, and Bot Framework
# signing keys that are this suite's own, so Teams::ActivityAuthenticator runs for
# real against tokens the test signs.
module TeamsTestHelper
  TEAMS_APP_ID = "e5dbb40e-0000-4000-8000-00000000b075"
  TEAMS_HOME_TENANT = "79e1cf7c-0000-4000-8000-0000000000aa"
  TEAMS_CUSTOMER_TENANT = "37b6f4fa-0000-4000-8000-0000000000bb"
  TEAMS_SERVICE_URL = "https://smba.trafficmanager.net/amer/#{TEAMS_CUSTOMER_TENANT}/".freeze
  BOT_FRAMEWORK_OPENID = "https://login.botframework.com/v1/.well-known/openidconfiguration"
  BOT_FRAMEWORK_JWKS = "https://login.botframework.com/v1/.well-known/keys"
  TEAMS_SIGNING_KID = "test-bot-framework-key"

  def teams_signing_key
    @teams_signing_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def teams_app_key
    @teams_app_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def with_teams_enabled
    Teams::TokenService.forget!
    Settings.stubs(:teams).returns(Hashie::Mash.new(
      app_id: TEAMS_APP_ID, home_tenant_id: TEAMS_HOME_TENANT, cloud: "public",
      private_key: teams_app_key.to_pem, certificate_thumbprint: "38" * 20
    ))
  end

  def stub_teams_token!(tenant: TEAMS_HOME_TENANT, token: "bot-token")
    stub_request(:post, "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { access_token: token, expires_in: 3600, token_type: "Bearer" }.to_json)
  end

  def stub_bot_framework_keys!(endorsements: [ "msteams" ])
    jwk = JWT::JWK.new(teams_signing_key.public_key, kid: TEAMS_SIGNING_KID).export
                  .merge(endorsements: endorsements)
    stub_request(:get, BOT_FRAMEWORK_OPENID)
      .to_return(status: 200, body: { jwks_uri: BOT_FRAMEWORK_JWKS }.to_json)
    stub_request(:get, BOT_FRAMEWORK_JWKS).to_return(status: 200, body: { keys: [ jwk ] }.to_json)
  end

  def bot_framework_token(service_url: TEAMS_SERVICE_URL, aud: TEAMS_APP_ID, iss: "https://api.botframework.com",
                          expires_at: 10.minutes.from_now, kid: TEAMS_SIGNING_KID)
    claims = { iss: iss, aud: aud, serviceurl: service_url, nbf: 1.minute.ago.to_i, exp: expires_at.to_i }
    JWT.encode(claims, teams_signing_key, "RS256", { kid: kid })
  end

  # A Teams message as the Bot Connector delivers it. `mention: true` puts the
  # bot's mention entity in, the way picking the bot from the @ list does.
  def teams_activity(text: "deploy", conversation_type: "channel", mention: true, from: {}, **overrides)
    channel = "19:abc@thread.tacv2"
    conversation_id = conversation_type == "personal" ? "a:1personal" : "#{channel};messageid=1700000000001"
    {
      "type" => "message", "id" => "1700000000002", "channelId" => "msteams", "serviceUrl" => TEAMS_SERVICE_URL,
      "from" => { "id" => "29:user", "name" => "Olo Brockhouse", "aadObjectId" => "b130c271-0000-4000-8000-000000000001" }
                .merge(from),
      "recipient" => { "id" => "28:#{TEAMS_APP_ID}", "name" => "Aixle Flow" },
      "conversation" => { "id" => conversation_id, "conversationType" => conversation_type,
                          "tenantId" => TEAMS_CUSTOMER_TENANT },
      "channelData" => { "tenant" => { "id" => TEAMS_CUSTOMER_TENANT },
                         "team" => { "id" => "19:team@thread.tacv2", "name" => "Sales" },
                         "channel" => { "id" => channel, "name" => "Onboarding" } },
      "text" => mention ? "<at>Aixle Flow</at> #{text}" : text,
      "entities" => (mention ? [ { "type" => "mention", "text" => "<at>Aixle Flow</at>",
                                    "mentioned" => { "id" => "28:#{TEAMS_APP_ID}", "name" => "Aixle Flow" } } ] : [])
    }.merge(overrides.transform_keys(&:to_s))
  end
end
