# frozen_string_literal: true

require "test_helper"

# Runners::MachineRegistration: "Add machine" (docs/design/agent-runtimes/DESIGN.md §6.3).
class Runners::MachineRegistrationTest < ActiveSupport::TestCase
  GATEWAY = "https://flow.example.com"

  setup { @runner = create(:runner, :manual) }

  test "mints a single-use token valid for an hour, with the recommended version's binaries from the pins" do
    freeze_time
    registration = Runners::MachineRegistration.issue!(@runner, gateway_url: GATEWAY)

    credential = RunnerCredential.find_by_token(registration.token, kind: :registration)
    assert_equal @runner, credential.runner
    assert_equal 1.hour.from_now, registration.expires_at
    assert_equal registration.expires_at, credential.expires_at
    assert_equal GATEWAY, registration.gateway_url

    version = Settings.runners.release.recommended_version
    assert_equal version, registration.version
    assert_equal %w[linux-amd64 linux-arm64], registration.binaries.map(&:platform)
    registration.binaries.each do |binary|
      assert_equal "#{GATEWAY}/runner/v1/releases/#{version}/#{binary.platform}", binary.url
      assert_equal Runners::Release.binary(version, binary.platform).sha256, binary.sha256
    end
  end

  test "the token records the user who asked for it" do
    user = create(:user)

    Runners::MachineRegistration.issue!(@runner, gateway_url: GATEWAY, created_by: user)

    assert_equal user, RunnerCredential.sole.created_by
  end

  test "stores only the token's digest" do
    registration = Runners::MachineRegistration.issue!(@runner, gateway_url: GATEWAY)

    assert_equal RunnerCredential.digest(registration.token), RunnerCredential.sole.token_digest
    assert_not_includes RunnerCredential.sole.attributes.values.map(&:to_s), registration.token
  end

  test "a revoked or deleted runner is refused with runner_revoked and mints nothing" do
    deleted = create(:runner, :manual, company: @runner.company)
    @runner.revoke!
    deleted.soft_delete!

    reasons = [ @runner, deleted ].map do |runner|
      assert_raises(Runners::Credentials::Refused) { Runners::MachineRegistration.issue!(runner, gateway_url: GATEWAY) }.reason
    end

    assert_equal %w[runner_revoked runner_revoked], reasons
    assert_empty RunnerCredential.where(kind: :registration)
  end

  test "only a manual runner registers machines" do
    error = assert_raises(Runners::Credentials::Refused) do
      Runners::MachineRegistration.issue!(create(:runner, :coder), gateway_url: GATEWAY)
    end

    assert_equal "runner_not_manual", error.reason
    assert_empty RunnerCredential.all
  end

  test "without a recommended version there is nothing to install, and no token is minted" do
    pins = Runners::Release.pins.with(recommended_version: nil)
    Runners::Release.stubs(:pins).returns(pins)

    error = assert_raises(Runners::Credentials::Refused) { Runners::MachineRegistration.issue!(@runner, gateway_url: GATEWAY) }

    assert_equal "no_runner_release", error.reason
    assert_empty RunnerCredential.all
  end
end
