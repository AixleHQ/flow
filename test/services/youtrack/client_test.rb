# frozen_string_literal: true

require "test_helper"

class Youtrack::ClientTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @integration = create(:integration, :active, provider: :youtrack, company: @company,
      settings: { "base_url" => "https://youtrack.example.com", "youtrack_project_id" => "0-1" })
    @integration.credentials_data = { permanent_token: "perm:secret" }
    @integration.save!
  end

  test "pins a checked public address and rejects a rebound private address" do
    UrlSafetyValidator.stubs(:resolved_addresses).returns(
      [ IPAddr.new("93.184.216.34") ], [ IPAddr.new("10.0.0.1") ])
    client = Youtrack::Client.new(@integration)
    assert_raises(Youtrack::Client::Error) { client.me }
  end

  test "rejects an oversized response before parsing it" do
    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new("93.184.216.34") ])
    stub_request(:get, "https://youtrack.example.com/api/users/me?fields=id%2Clogin%2Cname")
      .to_return(status: 200, body: "a" * (Youtrack::Client::MAX_BYTES + 1))

    error = assert_raises(Youtrack::Client::Error) { Youtrack::Client.new(@integration).me }
    assert_equal "YouTrack response is too large", error.message
  end

  test "a client obtained before disconnect cannot send another request" do
    client = Youtrack::Client.new(@integration)
    Integration.find(@integration.id).destroy!

    error = assert_raises(Youtrack::Client::Error) { client.me }
    assert_equal "YouTrack is not connected for this project", error.message
  end

  test "does not follow redirects or expose their destination" do
    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new("93.184.216.34") ])
    stub_request(:get, %r{https://youtrack.example.com/api/users/me})
      .to_return(status: 302, headers: { "Location" => "https://127.0.0.1/private" })

    error = assert_raises(Youtrack::Client::Error) { Youtrack::Client.new(@integration).me }
    assert_equal "YouTrack redirects are not allowed", error.message
  end
end
