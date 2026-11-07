# frozen_string_literal: true

require "test_helper"

# Runners::ImagePin against the OCI distribution API, as GHCR and Docker Hub
# answer it: an anonymous token from the registry's challenge, then the
# manifest's digest.
class Runners::ImagePinTest < ActiveSupport::TestCase
  DIGEST = "sha256:#{'c' * 64}".freeze

  setup do
    @pin = Runners::ImagePin.new
  end

  test "a reference pinned already is split and asks nothing" do
    assert_equal({ "image" => "ghcr.io/aixlehq/flow-claude-code", "digest" => DIGEST },
                 @pin.call("ghcr.io/aixlehq/flow-claude-code:1.2@#{DIGEST}"))
  end

  test "a tag is resolved through the registry's anonymous token" do
    stub_request(:head, "https://ghcr.io/v2/aixlehq/flow-claude-code/manifests/latest")
      .to_return(status: 401, headers: {
        "WWW-Authenticate" => 'Bearer realm="https://ghcr.io/token",service="ghcr.io",scope="repository:aixlehq/flow-claude-code:pull"'
      })
    stub_request(:get, "https://ghcr.io/token?scope=repository:aixlehq/flow-claude-code:pull&service=ghcr.io")
      .to_return(status: 200, body: { token: "anon" }.to_json)
    stub_request(:head, "https://ghcr.io/v2/aixlehq/flow-claude-code/manifests/latest")
      .with(headers: { "Authorization" => "Bearer anon" })
      .to_return(status: 200, headers: { "Docker-Content-Digest" => DIGEST })

    assert_equal({ "image" => "ghcr.io/aixlehq/flow-claude-code", "digest" => DIGEST },
                 @pin.call("ghcr.io/aixlehq/flow-claude-code"))
  end

  test "a Docker Hub name is looked up in its library, with a port kept as the registry's" do
    stub_request(:head, "https://registry-1.docker.io/v2/library/alpine/manifests/3.22")
      .to_return(status: 200, headers: { "Docker-Content-Digest" => DIGEST })
    stub_request(:head, "https://registry.local:5000/v2/team/agent/manifests/latest")
      .to_return(status: 200, headers: { "Docker-Content-Digest" => DIGEST })

    assert_equal "alpine", @pin.call("alpine:3.22")["image"]
    assert_equal "registry.local:5000/team/agent", @pin.call("registry.local:5000/team/agent")["image"]
  end

  test "an image the registry does not have fails with the registry's answer" do
    stub_request(:head, "https://ghcr.io/v2/aixlehq/nope/manifests/1").to_return(status: 404)

    error = assert_raises(Runners::ImagePin::Error) { @pin.call("ghcr.io/aixlehq/nope:1") }

    assert_equal "the registry ghcr.io answered 404 for ghcr.io/aixlehq/nope:1", error.message
  end
end
