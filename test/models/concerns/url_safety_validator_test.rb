# frozen_string_literal: true

require "test_helper"

class UrlSafetyValidatorTest < ActiveSupport::TestCase
  # ====================================================================
  # Blank / nil / invalid input
  # ====================================================================

  test "blank url returns 'is required'" do
    assert_equal [ "is required" ], UrlSafetyValidator.errors_for("")
    assert_equal [ "is required" ], UrlSafetyValidator.errors_for(nil)
    assert_equal [ "is required" ], UrlSafetyValidator.errors_for("   ")
  end

  test "unparseable url returns 'is not a valid URL'" do
    assert_equal [ "is not a valid URL" ], UrlSafetyValidator.errors_for("http://exa mple.com")
    assert_equal [ "is not a valid URL" ], UrlSafetyValidator.errors_for("http://[unterminated")
  end

  # ====================================================================
  # Scheme handling
  # ====================================================================

  test "rejects non-http schemes by default" do
    %w[ftp://example.com file:///etc/passwd javascript:alert(1) gopher://example.com].each do |url|
      errors = UrlSafetyValidator.errors_for(url)
      assert_includes errors, "must use http or https",
        "expected #{url} to be rejected for scheme"
    end
  end

  test "accepts http and https when require_https is false" do
    assert_empty UrlSafetyValidator.errors_for("http://example.com")
    assert_empty UrlSafetyValidator.errors_for("https://example.com")
  end

  test "rejects http when require_https is true" do
    errors = UrlSafetyValidator.errors_for("http://example.com", require_https: true)
    assert_includes errors, "must use https"
  end

  test "accepts https when require_https is true" do
    assert_empty UrlSafetyValidator.errors_for("https://example.com", require_https: true)
  end

  # ====================================================================
  # BLOCKED_HOSTS
  # ====================================================================

  test "rejects each BLOCKED_HOSTS entry" do
    UrlSafetyValidator::BLOCKED_HOSTS.each do |host|
      errors = UrlSafetyValidator.errors_for("https://#{host}")
      assert_includes errors, "cannot point to internal services",
        "expected #{host} to be rejected as a blocked host"
    end
  end

  test "blocked host matching is case-insensitive" do
    errors = UrlSafetyValidator.errors_for("https://LOCALHOST")
    assert_includes errors, "cannot point to internal services"
  end

  # ====================================================================
  # IPv4 SSRF protection
  # ====================================================================

  test "rejects IPv4 private CIDRs" do
    %w[
      http://10.0.0.1
      http://10.255.255.255
      http://172.16.0.1
      http://172.31.255.255
      http://192.168.0.1
      http://192.168.255.255
    ].each do |url|
      errors = UrlSafetyValidator.errors_for(url)
      assert_includes errors, "cannot point to private or internal network addresses",
        "expected #{url} to be rejected"
    end
  end

  test "rejects IPv4 loopback" do
    errors = UrlSafetyValidator.errors_for("http://127.0.0.1")
    assert_includes errors, "cannot point to private or internal network addresses"

    errors = UrlSafetyValidator.errors_for("http://127.0.0.2:8080")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "rejects IPv4 link-local (cloud metadata)" do
    errors = UrlSafetyValidator.errors_for("http://169.254.169.254/latest/meta-data/")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  # ====================================================================
  # IPv6 SSRF protection — exercised via the predicate so the tests do
  # not depend on URI's version-specific bracket handling of `uri.host`.
  # ====================================================================

  test "private_or_loopback? recognises IPv6 loopback" do
    assert UrlSafetyValidator.private_or_loopback?("::1")
  end

  test "private_or_loopback? recognises IPv6 link-local" do
    assert UrlSafetyValidator.private_or_loopback?("fe80::1")
  end

  test "private_or_loopback? accepts a public IPv6" do
    refute UrlSafetyValidator.private_or_loopback?("2606:4700:4700::1111")
  end

  # ====================================================================
  # Hostname resolved to a private IP (libc getaddrinfo — the SAME resolver
  # Net::HTTP dials with, so validation cannot diverge from the connection).
  # ====================================================================

  test "rejects hostname that resolves to a private IPv4" do
    stub_resolve("internal.example.test", "10.0.0.5")

    errors = UrlSafetyValidator.errors_for("https://internal.example.test")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "rejects hostname that resolves to loopback" do
    stub_resolve("loop.example.test", "127.0.0.1")

    errors = UrlSafetyValidator.errors_for("https://loop.example.test")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "accepts hostname that resolves only to a public IP" do
    stub_resolve("public.example.test", "93.184.216.34")

    assert_empty UrlSafetyValidator.errors_for("https://public.example.test")
  end

  test "rejects hostname resolving to a mix of public and private addresses" do
    stub_resolve("mixed.example.test", "93.184.216.34", "10.0.0.5")

    errors = UrlSafetyValidator.errors_for("https://mixed.example.test")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "swallows resolver errors (unresolvable host) as not-private" do
    Addrinfo.stubs(:getaddrinfo).with("unresolved.example.test", nil, nil, :STREAM).raises(SocketError)

    assert_empty UrlSafetyValidator.errors_for("https://unresolved.example.test")
  end

  # ====================================================================
  # Host-encoding SSRF bypass — packed-numeric / octal / hex / unspecified
  # hosts that IPAddr and Resolv silently miss but glibc getaddrinfo (and thus
  # Net::HTTP) resolves to loopback / cloud-metadata. Not stubbed: libc parses
  # these numerically with no network, so the check is deterministic in-image.
  # ====================================================================

  test "rejects decimal-packed IPv4 pointing at cloud metadata" do
    errors = UrlSafetyValidator.errors_for("https://2852039166", require_https: true)
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "rejects hex-packed IPv4 pointing at cloud metadata" do
    errors = UrlSafetyValidator.errors_for("https://0xA9FEA9FE", require_https: true)
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "rejects decimal-packed IPv4 pointing at loopback" do
    errors = UrlSafetyValidator.errors_for("https://2130706433", require_https: true)
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "rejects dotted hex/octal IPv4 pointing at loopback" do
    %w[https://0x7f.0.0.1 https://0177.0.0.1].each do |url|
      errors = UrlSafetyValidator.errors_for(url, require_https: true)
      assert_includes errors, "cannot point to private or internal network addresses",
        "expected #{url} to be rejected"
    end
  end

  test "rejects the unspecified address 0.0.0.0 (OS-routed to loopback)" do
    errors = UrlSafetyValidator.errors_for("https://0.0.0.0", require_https: true)
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "private_or_loopback? recognises the IPv6 unspecified address" do
    assert UrlSafetyValidator.private_or_loopback?("::")
  end

  # ====================================================================
  # Trusted hosts allowlist (split-horizon DNS bypass)
  # ====================================================================

  test "skips DNS-resolution rejection for trusted hostname (split-horizon DNS)" do
    UrlSafetyValidator.stubs(:trusted_hosts).returns([ "coder.staging.aixle.com" ])
    stub_resolve("coder.staging.aixle.com", "10.0.0.5")

    assert_empty UrlSafetyValidator.errors_for("https://coder.staging.aixle.com")
  end

  test "trusted_host? match is case-insensitive on the submitted host" do
    UrlSafetyValidator.stubs(:trusted_hosts).returns([ "coder.staging.aixle.com" ])
    stub_resolve("coder.staging.aixle.com", "10.0.0.5")

    assert_empty UrlSafetyValidator.errors_for("https://Coder.Staging.Aixle.Com")
  end

  test "trusted_hosts_override allows a private-resolving host for a single call-site" do
    stub_resolve("coder.coder.svc.cluster.local", "10.0.0.5")

    assert_empty UrlSafetyValidator.errors_for(
      "http://coder.coder.svc.cluster.local",
      trusted_hosts_override: [ "coder.coder.svc.cluster.local" ]
    )
  end

  test "trusted hosts allowlist does not bypass literal private IP" do
    UrlSafetyValidator.stubs(:trusted_hosts).returns([ "10.0.0.5" ])

    errors = UrlSafetyValidator.errors_for("http://10.0.0.5")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "trusted hosts allowlist does not bypass BLOCKED_HOSTS" do
    UrlSafetyValidator.stubs(:trusted_hosts).returns([ "localhost" ])

    errors = UrlSafetyValidator.errors_for("https://localhost")
    assert_includes errors, "cannot point to internal services"
  end

  test "non-trusted hostname resolving to private is still rejected" do
    UrlSafetyValidator.stubs(:trusted_hosts).returns([ "coder.staging.aixle.com" ])
    stub_resolve("other.example.test", "10.0.0.5")

    errors = UrlSafetyValidator.errors_for("https://other.example.test")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  # ====================================================================
  # resolve_public_ipv4 (split-horizon outbound resolution)
  # ====================================================================

  test "resolve_public_ipv4 returns first public A record" do
    public_a = Resolv::DNS::Resource::IN::A.new("93.184.216.34")
    private_a = Resolv::DNS::Resource::IN::A.new("10.0.0.5")

    dns = mock("dns")
    dns.expects(:timeouts=).with(UrlSafetyValidator::PUBLIC_DNS_TIMEOUTS)
    dns.expects(:getresources).with("public.example.test", Resolv::DNS::Resource::IN::A)
       .returns([ private_a, public_a ])

    Resolv::DNS.expects(:open)
               .with(nameserver: UrlSafetyValidator::PUBLIC_DNS_NAMESERVERS)
               .yields(dns)

    assert_equal "93.184.216.34", UrlSafetyValidator.resolve_public_ipv4("public.example.test")
  end

  test "resolve_public_ipv4 returns nil when only private addresses are returned" do
    private_a = Resolv::DNS::Resource::IN::A.new("10.0.0.5")

    dns = mock("dns")
    dns.expects(:timeouts=).with(UrlSafetyValidator::PUBLIC_DNS_TIMEOUTS)
    dns.expects(:getresources).with("split.example.test", Resolv::DNS::Resource::IN::A)
       .returns([ private_a ])

    Resolv::DNS.expects(:open)
               .with(nameserver: UrlSafetyValidator::PUBLIC_DNS_NAMESERVERS)
               .yields(dns)

    assert_nil UrlSafetyValidator.resolve_public_ipv4("split.example.test")
  end

  test "resolve_public_ipv4 swallows resolver errors and returns nil" do
    Resolv::DNS.expects(:open)
               .with(nameserver: UrlSafetyValidator::PUBLIC_DNS_NAMESERVERS)
               .raises(Resolv::ResolvError)

    assert_nil UrlSafetyValidator.resolve_public_ipv4("broken.example.test")
  end

  test "resolve_public_ipv4 returns nil for blank host" do
    assert_nil UrlSafetyValidator.resolve_public_ipv4("")
    assert_nil UrlSafetyValidator.resolve_public_ipv4(nil)
  end

  # ====================================================================
  # Aggregation
  # ====================================================================

  test "accumulates multiple errors when several rules fail" do
    errors = UrlSafetyValidator.errors_for("ftp://10.0.0.1")
    assert_includes errors, "must use http or https"
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  # ====================================================================
  # safe?
  # ====================================================================

  test "safe? returns true for a valid public https URL" do
    assert UrlSafetyValidator.safe?("https://example.com")
  end

  test "safe? returns false for a blocked URL" do
    refute UrlSafetyValidator.safe?("http://127.0.0.1")
  end

  private

  # Stub the libc resolver (getaddrinfo) — the SAME one Net::HTTP dials with —
  # to return the given addresses for `host`, so hostname-resolution tests don't
  # depend on real DNS.
  def stub_resolve(host, *ips)
    Addrinfo.stubs(:getaddrinfo)
            .with(host, nil, nil, :STREAM)
            .returns(ips.map { |ip| Addrinfo.ip(ip) })
  end
end
