# frozen_string_literal: true

require "test_helper"

class Teams::TokenServiceTest < ActiveSupport::TestCase
  setup { with_teams_enabled }

  test "the bot's token comes from its home tenant, proved with the certificate, and is reused" do
    stub = stub_teams_token!.with { |request|
      form = URI.decode_www_form(request.body).to_h
      claims = JWT.decode(form["client_assertion"], teams_app_key.public_key, true, algorithms: [ "RS256" ]).first
      form["scope"] == "https://api.botframework.com/.default" &&
        form["client_assertion_type"] == "urn:ietf:params:oauth:client-assertion-type:jwt-bearer" &&
        claims["aud"] == "https://login.microsoftonline.com/#{TEAMS_HOME_TENANT}/oauth2/v2.0/token" &&
        form["client_secret"].nil?
    }

    2.times { assert_equal "bot-token", Teams::TokenService.bot_token }

    assert_requested stub, times: 1
  end

  test "a Graph token is asked for in the customer's tenant" do
    stub = stub_teams_token!(tenant: TEAMS_CUSTOMER_TENANT, token: "graph-token")
             .with(body: hash_including("scope" => "https://graph.microsoft.com/.default"))

    assert_equal "graph-token", Teams::TokenService.graph_token(TEAMS_CUSTOMER_TENANT)
    assert_requested stub
  end

  test "an Entra refusal is an error carrying its status" do
    stub_request(:post, "https://login.microsoftonline.com/#{TEAMS_HOME_TENANT}/oauth2/v2.0/token")
      .to_return(status: 401, body: { error: "invalid_client", error_description: "AADSTS700027: bad assertion" }.to_json)

    error = assert_raises(Teams::Error) { Teams::TokenService.bot_token }
    assert_equal 401, error.status
    assert_match(/AADSTS700027/, error.message)
  end

  test "nothing is asked for a tenant id that is not one" do
    assert_raises(Teams::Error) { Teams::TokenService.graph_token("../common") }
  end

  test "an unconfigured deployment asks for nothing" do
    Settings.stubs(:teams).returns(Hashie::Mash.new(app_id: TEAMS_APP_ID))

    assert_not Teams::Config.enabled?
    assert_raises(Teams::Error) { Teams::TokenService.bot_token }
  end
end
