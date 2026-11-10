# frozen_string_literal: true

require "test_helper"

# Runners::Version: X-Aixle-Runner-Version as strict SemVer 2.0, ordered by its
# precedence (runner/protocol/PROTOCOL.md §1).
class Runners::VersionTest < ActiveSupport::TestCase
  test "only strict semantic versions parse" do
    %w[0.1.0 1.4.0 1.5.0-rc.1+build.7 0.0.0-dev 10.20.30].each { |value| assert Runners::Version.valid?(value), value }
    [ "", "1.4", "v1.4.0", "01.2.3", "1.2.3-01", "1.2.3-..", "1.2.3-", "1.2.3+", "latest", " 1.4.0", "1.4.0\n", nil, 1 ].each do |value|
      assert_not Runners::Version.valid?(value), value.inspect
    end
  end

  test "versions follow SemVer precedence, with build metadata ignored" do
    # semver.org §11, ascending.
    ordered = %w[0.0.0-dev 0.1.0 1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11
                 1.0.0-rc.1 1.0.0 1.0.1 1.1.0 2.0.0 10.0.0].map { |value| Runners::Version.parse(value) }

    ordered.each_with_index do |version, index|
      ordered.each_with_index do |other, other_index|
        assert_equal index <=> other_index, version <=> other, "#{version} <=> #{other}"
      end
    end
    assert_equal 0, Runners::Version.parse("1.4.0+a") <=> Runners::Version.parse("1.4.0+b")
    assert_nil Runners::Version.parse("1.4.0") <=> "1.4.0"
  end
end
