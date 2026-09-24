# frozen_string_literal: true

require "test_helper"

# Contract test for the adapter FakeTemplatesRepository stands in for.
class Templates::RepositoryClientTest < ActiveSupport::TestCase
  SHA = "0123456789abcdef0123456789abcdef01234567"
  COMMITS_URL = "https://api.github.com/repos/AixleHQ/flow-templates/commits/main"
  TARBALL_URL = "https://codeload.github.com/AixleHQ/flow-templates/tar.gz/#{SHA}".freeze

  test "head_sha asks the commits API for the bare sha of main" do
    stub_request(:get, COMMITS_URL).with(headers: { "Accept" => "application/vnd.github.sha" })
                                   .to_return(status: 200, body: "#{SHA}\n")

    assert_equal SHA, Templates::RepositoryClient.new.head_sha
  end

  test "head_sha refuses anything that is not a commit id" do
    stub_request(:get, COMMITS_URL).to_return(status: 200, body: "<html>rate limited</html>")

    assert_raises(Templates::RepositoryClient::Error) { Templates::RepositoryClient.new.head_sha }
  end

  test "a non-success response raises with the status" do
    stub_request(:get, COMMITS_URL).to_return(status: 403, body: "{}")

    error = assert_raises(Templates::RepositoryClient::Error) { Templates::RepositoryClient.new.head_sha }
    assert_match(/403/, error.message)
  end

  test "tarball downloads the archive of that exact commit" do
    archive = FakeTemplatesRepository.gzip_tar("flow-templates-#{SHA}/README.md" => "hello")
    stub_request(:get, TARBALL_URL).to_return(status: 200, body: archive)

    assert_equal archive, Templates::RepositoryClient.new.tarball(SHA)
  end

  test "the public-read token goes to api.github.com only, never to codeload" do
    Settings.github.stubs(:read_token).returns("public-read")
    stub_request(:get, COMMITS_URL).with(headers: { "Authorization" => "Bearer public-read" }).to_return(body: SHA)
    stub_request(:get, TARBALL_URL).to_return(body: "x")

    client = Templates::RepositoryClient.new
    client.head_sha
    client.tarball(SHA)

    assert_requested(:get, TARBALL_URL) { |request| !request.headers.key?("Authorization") }
  end
end
