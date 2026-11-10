# frozen_string_literal: true

require "test_helper"

# Runners::Release: the platform's runner pins, the `runners.release` block of
# config/settings.yml read as Settings.runners.release
# (docs/design/agent-runtimes/DESIGN.md §14.2, §14.4).
class Runners::ReleaseTest < ActiveSupport::TestCase
  AMD64 = "a" * 64
  ARM64 = "b" * 64
  PINS = {
    "protocol_supported" => [ 1 ], "min_version" => "1.2.0", "recommended_version" => "1.5.0",
    "download_url" => "https://github.com/AixleHQ/flow/releases/download/runner-v%{version}/aixle-runner-%{platform}",
    "binaries" => { "1.5.0" => { "linux-amd64" => { "sha256" => AMD64 }, "linux-arm64" => { "sha256" => ARM64.upcase } } }
  }.freeze

  setup do
    @runner = create(:runner, :manual)
    @environment = registered_environment
  end

  def pin(overrides = {})
    Runners::Release.stubs(:pins).returns(Runners::Release.parse(PINS.merge(overrides)))
  end

  def registered_environment(arch: "amd64")
    create(:runner_environment, runner: @runner, os: "linux", arch: arch, runner_version: "1.4.0", protocol_version: "1")
  end

  # The digests of runner-v0.1.0's checksums.txt
  # (https://github.com/AixleHQ/flow/releases/tag/runner-v0.1.0).
  RELEASED = {
    "0.1.0" => { "linux-amd64" => "55af0ecb22c70f52ca4213f7f310c6321ba0e1d175545f663c1c948107caad44",
                 "linux-arm64" => "e27d43e8d29ec520f5868b4394d66c9e95ea7476ffc3ee3d0a85e6b259527441" }
  }.freeze

  test "the committed pins are config/settings.yml's runners.release block, read through Settings" do
    assert_equal({ "protocol_supported" => [ 1 ], "min_version" => nil, "recommended_version" => "0.1.0",
                   "download_url" => PINS["download_url"],
                   "binaries" => RELEASED.transform_values { |platforms| platforms.transform_values { |digest| { "sha256" => digest } } } },
                 Settings.runners.release.to_h.deep_stringify_keys)
    pins = Runners::Release.pins
    assert_equal [ 1 ], pins.protocol_supported
    assert_nil pins.min_version
    assert_equal Runners::Version.parse("0.1.0"), pins.recommended_version
    assert_equal RELEASED, pins.binaries
    assert_equal "https://github.com/AixleHQ/flow/releases/download/runner-v0.1.0/aixle-runner-linux-amd64",
                 Runners::Release.binary("0.1.0", "linux-amd64").url
  end

  # config/initializers/runner_release.rb calls Runners::Release.pins once the
  # app is loaded, so an invalid block stops the boot with this error.
  test "an invalid runners.release block makes the pins raise InvalidPins" do
    settings = Config.load_files({ "runners" => { "release" => PINS.merge("min_version" => "1.2") } })
    Settings.stubs(:runners).returns(settings.runners)
    Runners::Release.reset!

    error = assert_raises(Runners::Release::InvalidPins) { Runners::Release.pins }
    assert_equal "config/settings.yml runners.release: min_version \"1.2\" is not a semantic version", error.message
  ensure
    Runners::Release.reset!
  end

  # The path a real pin takes, YAML to Settings, so dotted version keys and
  # the `<os>-<arch>` keys go through the Config gem's options and back.
  test "pinned binaries and a recommended version survive the Config gem" do
    settings = Config.load_files({ "runners" => { "release" => PINS.deep_dup } })
    Settings.stubs(:runners).returns(settings.runners)
    Runners::Release.reset!

    assert_equal Runners::Version.parse("1.5.0"), Runners::Release.pins.recommended_version
    binary = Runners::Release.binary("1.5.0", "linux-amd64")
    assert_equal AMD64, binary.sha256
    assert_equal "https://github.com/AixleHQ/flow/releases/download/runner-v1.5.0/aixle-runner-linux-amd64", binary.url
    assert_equal ARM64, Runners::Release.checksums("1.5.0").binaries["linux-arm64"]
    assert_equal Runners::Release::Offer.new(version: "1.5.0", sha256: AMD64),
                 Runners::Release.update_for(@environment, runner_version: "1.4.0")
  ensure
    Runners::Release.reset!
  end

  test "the parsed pins are kept until reset" do
    Runners::Release.reset!
    first = Runners::Release.pins

    assert_same first, Runners::Release.pins
    Runners::Release.reset!
    assert_not_same first, Runners::Release.pins
    assert_equal first, Runners::Release.pins
  end

  test "the pins parse into versions and lowercase digests" do
    pins = Runners::Release.parse(PINS)

    assert_equal Runners::Version.parse("1.2.0"), pins.min_version
    assert_equal Runners::Version.parse("1.5.0"), pins.recommended_version
    assert_equal({ "linux-amd64" => AMD64, "linux-arm64" => ARM64 }, pins.binaries["1.5.0"])
  end

  test "invalid pins are refused with the key that is wrong" do
    {
      { "protocol_supported" => [] } => "protocol_supported",
      { "protocol_supported" => [ 1, 2 ] } => "does not implement",
      { "protocol_supported" => [ "1" ] } => "protocol_supported",
      { "min_version" => "1.2" } => "min_version",
      { "recommended_version" => "v1.5.0" } => "recommended_version",
      { "min_version" => "1.6.0" } => "below min_version",
      { "recommended_version" => "1.6.0" } => "no pinned binaries",
      { "download_url" => "https://example.com/aixle-runner" } => "download_url",
      { "download_url" => "ftp://example.com/%{version}/%{platform}" } => "download_url",
      { "download_url" => "https://example.test/%{version}/%{platform}/%{unexpected}" } => "cannot be filled in",
      { "download_url" => "https://example.test/a%2Fb/%{version}/%{platform}" } => "cannot be filled in",
      { "download_url" => "https://example.test/%{version}/%{platform}/%" } => "cannot be filled in",
      { "binaries" => [] } => "binaries",
      { "binaries" => { "latest" => { "linux-amd64" => { "sha256" => AMD64 } } } } => "not a semantic version",
      { "binaries" => { "1.5.0" => {} } } => "map of platforms",
      { "binaries" => { "1.5.0" => { "darwin-arm64" => { "sha256" => AMD64 } } } } => "darwin-arm64",
      { "binaries" => { "1.5.0" => { "linux-amd64" => { "sha256" => "abc" } } } } => "sha256",
      { "binaries" => { "1.5.0" => { "linux-amd64" => { "sha256" => AMD64, "url" => "x" } } } } => "sha256",
      { "signing" => true } => "unknown keys"
    }.each do |overrides, message|
      error = assert_raises(Runners::Release::InvalidPins, overrides.inspect) { Runners::Release.parse(PINS.merge(overrides)) }
      assert_includes error.message, message, overrides.inspect
    end
  end

  test "the minimum and the protocol come from the pins" do
    pin

    assert Runners::Release.unsupported_version?("1.1.9")
    assert Runners::Release.unsupported_version?("1.2.0-rc.1")
    assert_not Runners::Release.unsupported_version?("1.2.0")
    assert_not Runners::Release.unsupported_version?("2.0.0")
    assert Runners::Release.protocol_supported?("1")
    [ "2", "1.0", "01", "", nil ].each { |value| assert_not Runners::Release.protocol_supported?(value), value.inspect }

    pin("min_version" => nil)
    assert_not Runners::Release.unsupported_version?("0.0.0-dev")
  end

  test "a pinned binary has the asset URL and the pinned digest; anything unpinned is nil" do
    pin

    binary = Runners::Release.binary("1.5.0", "linux-arm64")
    assert_equal "https://github.com/AixleHQ/flow/releases/download/runner-v1.5.0/aixle-runner-linux-arm64", binary.url
    assert_equal ARM64, binary.sha256
    assert_nil Runners::Release.binary("1.4.0", "linux-amd64")
    assert_nil Runners::Release.binary("1.5.0", "darwin-arm64")
    assert_equal({ "linux-amd64" => AMD64, "linux-arm64" => ARM64 }, Runners::Release.checksums("1.5.0").binaries)
    assert_nil Runners::Release.checksums("1.4.0")
  end

  test "an idle machine below the recommended version is offered its platform's binary" do
    pin

    offer = Runners::Release.update_for(@environment, runner_version: "1.4.0")
    assert_equal Runners::Release::Offer.new(version: "1.5.0", sha256: AMD64), offer
    arm = registered_environment(arch: "arm64")
    assert_equal ARM64, Runners::Release.update_for(arm, runner_version: "1.5.0-rc.1").sha256
  end

  test "no update at or above the recommended version, without a recommendation, or without the machine's binary" do
    pin
    assert_nil Runners::Release.update_for(@environment, runner_version: "1.5.0")
    assert_nil Runners::Release.update_for(@environment, runner_version: "1.6.0")
    assert_nil Runners::Release.update_for(registered_environment(arch: "riscv64"), runner_version: "1.4.0")

    pin("recommended_version" => nil)
    assert_nil Runners::Release.update_for(@environment, runner_version: "1.4.0")
  end

  test "no update while the machine holds a session or is not registered" do
    pin
    create(:runner_session, :holding, environment: @environment)
    assert_nil Runners::Release.update_for(@environment.reload, runner_version: "1.4.0")

    @environment.update!(current_session_id: nil, state: "failed")
    assert_nil Runners::Release.update_for(@environment, runner_version: "1.4.0")
  end

  test "no update for a machine or a runner that opted out" do
    pin
    @environment.update!(auto_update: false)
    assert_nil Runners::Release.update_for(@environment, runner_version: "1.4.0")

    @environment.update!(auto_update: true)
    @runner.update!(config: { "auto_update" => false })
    assert_nil Runners::Release.update_for(@environment.reload, runner_version: "1.4.0")

    @runner.update!(config: { "auto_update" => true })
    assert_not_nil Runners::Release.update_for(@environment.reload, runner_version: "1.4.0")
  end
end
