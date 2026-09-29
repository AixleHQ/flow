# frozen_string_literal: true

# Test hostnames are fictional and resolve nowhere, and SafeHttp refuses to dial a
# name it cannot resolve (an empty first answer is how a rebinding attack starts).
# A test that sends a request through SafeHttp resolves every name to one public
# address instead; literal IPs are still judged as themselves.
module PublicDnsHelper
  PUBLIC_TEST_ADDRESS = "93.184.215.14"

  def resolve_hosts_publicly!
    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new(PUBLIC_TEST_ADDRESS) ])
  end
end

ActiveSupport::TestCase.include(PublicDnsHelper)
