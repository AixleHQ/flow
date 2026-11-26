# frozen_string_literal: true

require "test_helper"

# Runners::MachineInstallScript (docs/design/agent-runtimes/add-machine.md §3.4):
# the rendering alone, without a request. The script run under a fake PATH is in
# RunnerGatewayMachineInstallTest.
class Runners::MachineInstallScriptTest < ActiveSupport::TestCase
  test "it writes the version, the gateway and each digest" do
    script = Runners::MachineInstallScript.render(
      version: "1.5.0", gateway_url: "https://flow.example",
      digests: { "linux-amd64" => "a" * 64, "linux-arm64" => "b" * 64 }
    )

    assert_includes script, "version=1.5.0\n"
    assert_includes script, "gateway=https://flow.example\n"
    assert_includes script, "linux-amd64) expected=#{'a' * 64} ;;"
    assert_includes script, "linux-arm64) expected=#{'b' * 64} ;;"
  end

  test "a value is written with shell escaping" do
    script = Runners::MachineInstallScript.render(
      version: "1.5.0", gateway_url: "https://x.example/'; id", digests: { "linux-amd64" => "a" * 64 }
    )

    assert_includes script, "gateway=#{Shellwords.escape("https://x.example/'; id")}\n"
    assert_not_includes script, "gateway=https://x.example/'; id"
  end
end
