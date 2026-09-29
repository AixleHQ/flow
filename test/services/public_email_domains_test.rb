# frozen_string_literal: true

require "test_helper"

class PublicEmailDomainsTest < ActiveSupport::TestCase
  test "it knows the common services" do
    assert_includes PublicEmailDomains, "gmail.com"
    assert_includes PublicEmailDomains, "outlook.com"
    assert_includes PublicEmailDomains, "yandex.ru"
    assert_includes PublicEmailDomains, "proton.me"
  end

  test "an organisation's own domain is not one" do
    assert_not PublicEmailDomains.include?("acme-robotics.example")
    assert_not PublicEmailDomains.include?("aixle.com")
  end

  # The domain reaches this from a form, where people type as they please.
  test "it reads a domain however it was typed" do
    assert_includes PublicEmailDomains, "  GMail.COM "
  end

  # A workspace on Google Workspace has its own domain and is a customer like any
  # other; only the shared service itself is refused.
  test "a domain hosted by one of them is still its own domain" do
    assert_not PublicEmailDomains.include?("mail.acme-robotics.example")
    assert_not PublicEmailDomains.include?("notgmail.com")
  end

  test "nothing at all is not one" do
    assert_not PublicEmailDomains.include?(nil)
    assert_not PublicEmailDomains.include?("")
  end
end
