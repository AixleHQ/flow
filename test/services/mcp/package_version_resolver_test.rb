# frozen_string_literal: true

require "test_helper"

module MCP
  class PackageVersionResolverTest < ActiveSupport::TestCase
    def unpinned(registry_type, identifier)
      { "kind" => "package", "registry_type" => registry_type, "identifier" => identifier,
        "version" => "latest", "version_pinned" => false }
    end

    test "pins an npm package to its current release" do
      stub_request(:get, "https://registry.npmjs.org/@scope%2Fpkg/latest").to_return(status: 200, body: { version: "2.3.4" }.to_json)

      assert_equal({ "version" => "2.3.4", "version_pinned" => true },
                   PackageVersionResolver.pin(unpinned("npm", "@scope/pkg")).slice("version", "version_pinned"))
    end

    test "pins a PyPI package to its current release" do
      stub_request(:get, "https://pypi.org/pypi/mcp-server-git/json").to_return(status: 200, body: { info: { version: "0.6.2" } }.to_json)

      assert_equal "0.6.2", PackageVersionResolver.pin(unpinned("pypi", "mcp-server-git"))["version"]
    end

    test "leaves a target alone when the registry answers with something that is not a release" do
      stub_request(:get, "https://registry.npmjs.org/pkg/latest").to_return(status: 200, body: { version: "next" }.to_json)

      assert_equal({ "version" => "latest", "version_pinned" => false },
                   PackageVersionResolver.pin(unpinned("npm", "pkg")).slice("version", "version_pinned"))
    end

    test "never asks a registry about a name it would not accept" do
      assert_nil PackageVersionResolver.latest("npm", "../../evil")
      assert_nil PackageVersionResolver.latest("pypi", "a/b")
    end

    test "a target that is already pinned, or not a package, is returned as is" do
      pinned = unpinned("npm", "pkg").merge("version" => "1.0.0", "version_pinned" => true)
      remote = { "kind" => "remote", "url" => "https://example.com" }

      assert_same pinned, PackageVersionResolver.pin(pinned)
      assert_same remote, PackageVersionResolver.pin(remote)
    end
  end
end
