# frozen_string_literal: true

require "test_helper"

# Every link the app emails is built from ActionMailer's default_url_options.
# config/application.rb derives those from Settings.domain and Settings.protocol,
# so they follow DOMAIN — the address a browser actually reaches the app at.
#
# An environment file that sets them again silently wins, and the usual
# replacement is a hardcoded host plus the port the process listens on. Those two
# ports are the same only when nothing is published in front of the app: behind a
# port mapping, a proxy or a container they differ, and every emailed link points
# at a port the recipient cannot open. development.rb carried exactly that
# override, which is why sign-in links in a second dev stack led back to the
# first one.
#
# Nothing in a test run exercises the development environment, so the guard has
# to read the config files themselves.
class MailerUrlOptionsTest < ActiveSupport::TestCase
  ENVIRONMENT_FILES = Rails.root.glob("config/environments/*.rb").freeze
  OVERRIDE = /^\s*config\.action_mailer\.default_url_options\s*=/

  test "mailer links are addressed the way the browser reaches the app" do
    assert_equal Settings.domain, ActionMailer::Base.default_url_options[:host]
    assert_equal Settings.protocol, ActionMailer::Base.default_url_options[:protocol]
  end

  test "the host carries its port rather than a separate port option" do
    # A `port:` alongside a host that already names one makes Rails split the
    # host and then let the option win, which is the shape that loses the port.
    assert_nil ActionMailer::Base.default_url_options[:port]
  end

  test "no environment overrides the mailer's default_url_options" do
    assert ENVIRONMENT_FILES.any?, "no config/environments/*.rb found"

    offenders = ENVIRONMENT_FILES.select { |file| file.read.match?(OVERRIDE) }

    assert_empty offenders.map { |file| file.relative_path_from(Rails.root).to_s },
      "these set action_mailer.default_url_options, overriding the DOMAIN-derived value in application.rb"
  end
end
