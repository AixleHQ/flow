# frozen_string_literal: true

require "test_helper"

class SafeHttpTest < ActiveSupport::TestCase
  URL = URI("https://mcp.example.com/mcp")

  def resolve_to(*addresses)
    UrlSafetyValidator.stubs(:resolved_addresses).with("mcp.example.com").returns(addresses.map { |a| IPAddr.new(a) })
  end

  test "connects to the address it checked, keeping the name for TLS" do
    resolve_to("93.184.215.14")

    http = SafeHttp.http_for(URL, open_timeout: 5, read_timeout: 5)

    assert_equal "93.184.215.14", http.ipaddr
    assert_equal "mcp.example.com", http.address
    assert_predicate http, :use_ssl?
  end

  test "refuses a name any of whose addresses is internal" do
    resolve_to("93.184.215.14", "10.0.0.7")

    error = assert_raises(SafeHttp::UnsafeUrl) { SafeHttp.http_for(URL, open_timeout: 5, read_timeout: 5) }
    assert_match(/private or internal/, error.message)
  end

  # An empty first answer, then an internal one when the client looks again, is
  # the rebinding pattern; a name that does not resolve is not dialed.
  test "refuses a name that does not resolve" do
    resolve_to

    assert_raises(SafeHttp::UnsafeUrl) { SafeHttp.vetted_address(URL) }
  end

  test "judges a literal address as itself" do
    assert_equal "93.184.215.14", SafeHttp.vetted_address(URI("https://93.184.215.14/"))
    assert_raises(SafeHttp::UnsafeUrl) { SafeHttp.vetted_address(URI("http://169.254.169.254/latest")) }
    assert_raises(SafeHttp::UnsafeUrl) { SafeHttp.vetted_address(URI("http://[::ffff:127.0.0.1]/")) }
  end

  test "a trusted host resolves through internal DNS only when the call site says so" do
    resolve_to("10.0.0.5")

    assert_nil SafeHttp.vetted_address(URL, trusted_hosts: [ "mcp.example.com" ])
    assert_raises(SafeHttp::UnsafeUrl) { SafeHttp.vetted_address(URL) }
  end

  test "refuses what is not http" do
    assert_raises(SafeHttp::UnsafeUrl) { SafeHttp.vetted_address(URI("file:///etc/passwd")) }
    assert_raises(SafeHttp::UnsafeUrl) { SafeHttp.vetted_address(URI("http://localhost:3000/")) }
  end
end
