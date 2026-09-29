# frozen_string_literal: true

require "test_helper"

class DeploymentSelfServeSignupTest < ActiveSupport::TestCase
  def with(mode:, registration:)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: registration))
  end

  test "it takes both the hosted product and the operator's say-so" do
    with(mode: Deployment::SAAS, registration: true)

    assert Deployment.self_serve_signup?
  end

  test "the flag alone is not enough" do
    with(mode: Deployment::SELF_HOSTED, registration: true)
    assert_not Deployment.self_serve_signup?

    with(mode: Deployment::AWS_MARKETPLACE, registration: true)
    assert_not Deployment.self_serve_signup?
  end

  test "being the hosted product alone is not enough either" do
    with(mode: Deployment::SAAS, registration: false)

    assert_not Deployment.self_serve_signup?
  end

  # Anything but a true flag is off. The variable reaches this as a string from
  # the environment, and "maybe" must not read as yes.
  test "an unset or unreadable flag is off" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))

    Settings.stubs(:registration).returns(nil)
    assert_not Deployment.self_serve_signup?

    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: "true"))
    assert_not Deployment.self_serve_signup?
  end
end
