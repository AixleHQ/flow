# frozen_string_literal: true

require "test_helper"

class Auth::QrCodeTest < ActiveSupport::TestCase
  URI = "otpauth://totp/Flow:person@example.test?secret=JBSWY3DPEHPK3PXP&issuer=Flow"

  def decoded(text)
    Base64.strict_decode64(Auth::QrCode.data_uri(text).split(",", 2).last)
  end

  test "renders a data: URI holding SVG" do
    assert_match %r{\Adata:image/svg\+xml;base64,}, Auth::QrCode.data_uri(URI)
    assert_includes decoded(URI), "<svg"
  end

  test "the code carries its own light ground and quiet zone" do
    # A QR is read as dark-on-light. Left transparent it inherits the page — on a
    # dark theme that is dark-on-dark, and no scanner reads it.
    svg = decoded(URI)

    assert_includes svg, "ffffff"
    assert_includes svg, "000000"
  end

  test "the SVG scales to the space the page gives it" do
    # Without a viewBox the image carries fixed pixel dimensions and ignores the
    # width the page sets, which is how a QR ends up the wrong size to scan.
    assert_includes decoded(URI), "viewBox"
  end

  test "a blank payload renders nothing rather than an empty code" do
    assert_nil Auth::QrCode.data_uri(nil)
    assert_nil Auth::QrCode.data_uri("")
  end

  test "a longer payload still renders" do
    # An otpauth URI grows with the issuer and account name; a QR version too
    # small for the payload raises rather than truncating.
    long = "otpauth://totp/#{'Very Long Issuer Name ' * 5}:#{'a' * 60}@example.test?secret=JBSWY3DPEHPK3PXP"

    assert_includes decoded(long), "<svg"
  end
end
