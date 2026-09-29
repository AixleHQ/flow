# frozen_string_literal: true

require "test_helper"

# The two switches that must not drift apart: registration open, and a way to
# take payment. Apart, a workspace signs itself up, spends its free capacity and
# reaches a stop with no card to add — which nobody finds out until it happens to
# a customer.
#
# The initializer runs at boot and cannot be re-run here, so this tests the
# predicate it is built from, and pins the message it raises.
class RegistrationNeedsPaymentTest < ActiveSupport::TestCase
  def configure(mode:, registration:, stripe:)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: registration))
    Settings.stubs(:stripe).returns(
      stripe ? Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test") : Hashie::Mash.new
    )
  end

  def refused?
    Deployment.self_serve_signup? && !Billing::StripeClient.new.configured?
  end

  test "registration open with no payment provider is refused" do
    configure(mode: Deployment::SAAS, registration: true, stripe: false)

    assert refused?, "a deploy in this shape must not start"
  end

  test "registration open with a payment provider is fine" do
    configure(mode: Deployment::SAAS, registration: true, stripe: true)

    assert_not refused?
  end

  # The ordinary state of every installation today, and of prod: registration
  # closed, no Stripe, nothing to check.
  test "registration closed needs no payment provider" do
    configure(mode: Deployment::SAAS, registration: false, stripe: false)

    assert_not refused?
  end

  # Nobody signs themselves up outside the hosted product, so nobody can reach
  # the stop this guards against.
  test "the guard does not apply outside the hosted product" do
    configure(mode: Deployment::SELF_HOSTED, registration: true, stripe: false)
    assert_not refused?

    configure(mode: Deployment::AWS_MARKETPLACE, registration: true, stripe: false)
    assert_not refused?
  end

  # Half-configured is not configured: a key without a price cannot open a
  # checkout, so it must read as absent rather than as present.
  test "a half-configured provider counts as none" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: true))

    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: nil))
    assert refused?

    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: nil, price_id: "price_test"))
    assert refused?
  end

  # The initializer is the thing that actually stops the deploy; this is what
  # keeps the two from drifting.
  test "the initializer checks exactly this" do
    assert_includes initializer, "Deployment.self_serve_signup?"
    assert_includes initializer, "Billing::StripeClient.new.configured?"
    assert_includes initializer, "REGISTRATION_ENABLED is on but Stripe is not configured"
  end

  # Both predicates live in app/, and an initializer that names an autoloadable
  # constant raises NameError before Zeitwerk is ready — which broke the image
  # build rather than the deploy it was meant to guard.
  test "the check waits until after initialization" do
    assert_match(/after_initialize do\n\s*if Deployment\.self_serve_signup\?/, initializer)
  end

  private

  def initializer = Rails.root.join("config/initializers/required_env.rb").read
end
