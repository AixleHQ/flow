# frozen_string_literal: true

require "test_helper"

class Web::HowItWorksControllerTest < ActionDispatch::IntegrationTest
  setup { with_mode(Deployment::SAAS) }

  # Registration is off by default, so a suite about signing up says so rather
  # than inheriting whatever the environment left in the settings file.
  def with_mode(mode, registration: true)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: registration))
  end

  test "a stranger can read it" do
    get how_it_works_path

    assert_inertia_page "HowItWorks/ShowPage"
  end

  test "it publishes the installation's list price" do
    Settings.stubs(:pricing).returns(Hashie::Mash.new(queue_hourly_rate: 8))

    get how_it_works_path

    assert_inertia_props { |props| assert_in_delta 8.0, props[:queueHourlyRate] }
  end

  # The signup form links here. Someone who followed that link is signed in with
  # no workspace, which is exactly the state enforce_workspace sends back to the
  # form — so without its skip this page would bounce the only people it is for.
  test "someone part-way through signing up can read it" do
    sign_in_as(create(:user, password: AuthHelper::TEST_PASSWORD))

    get how_it_works_path

    assert_inertia_page "HowItWorks/ShowPage"
  end

  # The page sells a signup. While that is switched off it is selling something
  # nobody can buy.
  test "it is gone while registration is off" do
    with_mode(Deployment::SAAS, registration: false)

    get how_it_works_path

    assert_redirected_to root_path
  end

  # It sells a workspace a stranger can create and a price we invoice. Neither
  # exists anywhere else, so neither does the page.
  test "self-hosted has no such page" do
    with_mode(Deployment::SELF_HOSTED)

    get how_it_works_path

    assert_redirected_to root_path
  end

  test "marketplace has no such page" do
    with_mode(Deployment::AWS_MARKETPLACE)

    get how_it_works_path

    assert_redirected_to root_path
  end
end
