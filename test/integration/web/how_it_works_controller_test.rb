# frozen_string_literal: true

require "test_helper"

class Web::HowItWorksControllerTest < ActionDispatch::IntegrationTest
  setup { with_mode(Deployment::SAAS) }

  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
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
