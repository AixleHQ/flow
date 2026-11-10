# frozen_string_literal: true

require "test_helper"

# The callback proxy's ports (Settings.runners.proxy, DESIGN.md §6.9.3). A bad
# value fails late and only for some sessions, so a deploy refuses to boot on
# one, naming the variable.
#
# The initializer runs at boot and cannot be re-run here, so this tests the
# predicate it is built from, and pins that the initializer asks it.
class RunnerProxySettingsTest < ActiveSupport::TestCase
  def problems(port: 7690, base: 20_000, span: 10_000)
    Runners::Proxy.settings_problems(Hashie::Mash.new(port: port, host_port_base: base, host_port_span: span))
  end

  test "the defaults are fine" do
    assert_empty Runners::Proxy.settings_problems
    assert_empty problems
  end

  test "the sidecar's port must be in 1024..65535" do
    [ nil, "", "x", 0, 1023, 65_536 ].each do |port|
      assert_match(/\ARUNNER_PROXY_PORT must be in 1024\.\.65535/, problems(port: port).sole, port.inspect)
    end
    assert_empty problems(port: 1024)
    assert_empty problems(port: 65_535)
  end

  test "the sidecar's port must not be one of the agent image's" do
    Runners::Proxy::IMAGE_PORTS.each do |port|
      assert_match(/\ARUNNER_PROXY_PORT .* not #{port}\z/, problems(port: port).sole)
    end
  end

  test "the host port base must be at least 1024" do
    [ nil, "", 1023 ].each do |base|
      assert_match(/\ARUNNER_PROXY_HOST_PORT_BASE must be at least 1024/, problems(base: base).sole, base.inspect)
    end
    assert_empty problems(base: 1024)
  end

  test "the host port span must be at least 1" do
    [ nil, "", 0, -1 ].each do |span|
      assert_match(/\ARUNNER_PROXY_HOST_PORT_SPAN must be at least 1/, problems(span: span).sole, span.inspect)
    end
    assert_empty problems(span: 1)
  end

  test "the last host port must be at most 65535" do
    assert_empty problems(base: 60_000, span: 5536)
    assert_equal [ "RUNNER_PROXY_HOST_PORT_BASE + RUNNER_PROXY_HOST_PORT_SPAN - 1 must be at most 65535, not 65536" ],
                 problems(base: 60_000, span: 5537)
  end

  test "the initializer refuses to boot on the first problem, after initialization" do
    initializer = Rails.root.join("config/initializers/required_env.rb").read

    pattern = /after_initialize do\n.*Runners::Proxy\.settings_problems\.first\n\s*raise proxy_problem if proxy_problem/m

    assert_match pattern, initializer
  end
end
