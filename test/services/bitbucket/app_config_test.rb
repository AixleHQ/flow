# frozen_string_literal: true

require "test_helper"

module Bitbucket
  class AppConfigTest < ActiveSupport::TestCase
    test "app mode needs the app and the environment this deployment serves" do
      with_bitbucket_settings(app_mode: true)

      assert AppConfig.app_mode_enabled?
    end

    # Forge shares only an app's production environment, so a staging
    # deployment has no install link and installs through `forge install`.
    test "app mode needs no install link" do
      with_bitbucket_settings(app_mode: true, install_url: nil)

      assert AppConfig.app_mode_enabled?
      assert_nil AppConfig.forge_install_url
    end

    test "without the Forge identity Bitbucket connects with tokens only" do
      with_bitbucket_settings

      assert_not AppConfig.app_mode_enabled?
    end
  end
end
