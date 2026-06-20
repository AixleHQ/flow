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
  # Hostname resolved to a private IP (Resolv fallback)
  # ====================================================================

  test "rejects hostname that resolves to a private IPv4" do
    Resolv.stubs(:getaddresses).with("internal.example.test").returns([ "10.0.0.5" ])

    errors = UrlSafetyValidator.errors_for("https://internal.example.test")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "rejects hostname that resolves to loopback" do
    Resolv.stubs(:getaddresses).with("loop.example.test").returns([ "127.0.0.1" ])

    errors = UrlSafetyValidator.errors_for("https://loop.example.test")
    assert_includes errors, "cannot point to private or internal network addresses"
  end

  test "accepts hostname that resolves only to a public IP" do
    Resolv.stubs(:getaddresses).with("public.example.test").returns([ "93.184.216.34" ])

    assert_empty UrlSafetyValidator.errors_for("https://public.example.test")
  end

  test "swallows Resolv::ResolvError as not-private" do
    Resolv.stubs(:getaddresses).with("unresolved.example.test").raises(Resolv::ResolvError)

    assert_empty UrlSafetyValidator.errors_for("https://unresolved.example.test")
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
end
