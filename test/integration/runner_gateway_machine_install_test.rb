# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# GET /runner/v1/machine-install.sh (docs/design/agent-runtimes/add-machine.md §3.4, §5):
# the script of the "Linux service" tab, rendered from the platform's pins, and
# the script itself run under a fake PATH.
class RunnerGatewayMachineInstallTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  ARM64 = "b" * 64
  # What the fake `curl` writes as the binary; each test pins the digest it wants for it.
  BINARY = "#!/bin/sh\necho \"aixle-runner $*\" >> \"$FAKE_LOG\"\n"

  def pin(amd64:, arm64: ARM64, recommended: "1.5.0")
    pins = {
      "protocol_supported" => [ 1 ], "min_version" => nil, "recommended_version" => recommended,
      "download_url" => "https://github.com/AixleHQ/flow/releases/download/runner-v%{version}/aixle-runner-%{platform}",
      "binaries" => { "1.5.0" => { "linux-amd64" => { "sha256" => amd64 }, "linux-arm64" => { "sha256" => arm64 } } }
    }
    Runners::Release.stubs(:pins).returns(Runners::Release.parse(pins))
  end

  def sha(content) = Digest::SHA256.hexdigest(content)

  # == the endpoint ==

  test "it is public and no-store, and renders the pinned version, gateway and both digests" do
    pin(amd64: "a" * 64)

    get "/runner/v1/machine-install.sh"

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "text/x-shellscript", response.media_type
    body = response.body
    assert_includes body, "version=1.5.0\n"
    assert_includes body, "gateway=#{Shellwords.escape(Runners::MachineRegistration.gateway_url)}\n"
    assert_includes body, "linux-amd64) expected=#{'a' * 64} ;;"
    assert_includes body, "linux-arm64) expected=#{ARM64} ;;"
  end

  test "nothing but the pins and the gateway URL is in the body, whatever the request carries" do
    pin(amd64: "a" * 64)

    get "/runner/v1/machine-install.sh?token=arreg_x&name=evil", headers: { "Host" => "evil.example", "X-Forwarded-Host" => "evil.example" }

    assert_response :ok
    assert_not_includes response.body, "evil"
    assert_not_includes response.body, "arreg_x"
  end

  test "no recommended version is not found, and no-store" do
    pin(amd64: "a" * 64, recommended: nil)

    get "/runner/v1/machine-install.sh"

    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "with the committed pins it renders the recommended version's released digests" do
    get "/runner/v1/machine-install.sh"

    assert_response :ok
    pins = Runners::Release.pins
    version = pins.recommended_version.to_s
    assert_includes response.body, "version=#{version}\n"
    %w[linux-amd64 linux-arm64].each do |platform|
      assert_includes response.body, "#{platform}) expected=#{pins.binaries.dig(version, platform)} ;;"
    end
  end

  test "the rendered script is valid POSIX sh" do
    pin(amd64: "a" * 64)
    get "/runner/v1/machine-install.sh"

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "install.sh"), response.body)
      _out, err, status = Open3.capture3("sh", "-n", File.join(dir, "install.sh"))
      assert status.success?, err
    end
  end

  # == the script, run under a fake PATH ==

  def fake_bin(dir, uid: "0", systemctl: true)
    bin = File.join(dir, "fakebin")
    FileUtils.mkdir_p(bin)
    stub = lambda do |name, body|
      File.write(File.join(bin, name), "#!/bin/sh\n#{body}\n")
      FileUtils.chmod(0o755, File.join(bin, name))
    end
    stub.call("uname", <<~'SH')
      case "$1" in
        -m) echo "$FAKE_MACHINE" ;;
        -s) echo "$FAKE_KERNEL" ;;
      esac
    SH
    stub.call("id", "echo #{uid}")
    # `:no_unit`: a fresh machine, where no aixle-runner unit exists and every `systemctl` call about it fails.
    stub.call("systemctl", "echo 'Unit aixle-runner.service not found.' >&2\nexit 4") if systemctl == :no_unit
    stub.call("systemctl", "exit 0") if systemctl == true
    # curl -fsSL -o <file> <url>: records the URL and writes the fake binary.
    File.write(File.join(dir, "fake-binary"), BINARY)
    stub.call("curl", <<~'SH')
      echo "curl $*" >> "$FAKE_LOG"
      out=; while [ "$#" -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
      cp "$FAKE_BINARY" "$out"
    SH
    bin
  end

  def run_script(dir, *args, **machine)
    File.write(File.join(dir, "install.sh"), response.body)
    log = File.join(dir, "log")
    FileUtils.touch(log)
    bin = fake_bin(dir, **machine.slice(:uid, :systemctl))
    # `mktemp`, `sha256sum`, `chmod`, `rm` and `sh` come from the real system.
    env = { "PATH" => "#{bin}:/usr/bin:/bin", "FAKE_LOG" => log, "FAKE_BINARY" => File.join(dir, "fake-binary"),
            "FAKE_MACHINE" => machine.fetch(:machine, "x86_64"), "FAKE_KERNEL" => machine.fetch(:kernel, "Linux") }
    out, err, status = Open3.capture3(env, "/bin/sh", File.join(dir, "install.sh"), *args, unsetenv_others: true)
    [ out + err, status, File.read(log) ]
  end

  test "it downloads the pinned binary for each architecture, checks it, registers and starts the service" do
    { "x86_64" => "linux-amd64", "amd64" => "linux-amd64", "aarch64" => "linux-arm64", "arm64" => "linux-arm64" }.each do |machine, platform|
      pin(amd64: sha(BINARY), arm64: sha(BINARY))
      get "/runner/v1/machine-install.sh"

      Dir.mktmpdir do |dir|
        output, status, log = run_script(dir, "--token", "arreg_t'ok", "--name", "build-01", "--no-auto-update", machine: machine)

        assert status.success?, "#{machine}: #{output}"
        lines = log.lines.map(&:chomp)
        assert_equal "curl -fsSL -o #{lines[0][/-o (\S+)/, 1]} #{Runners::MachineRegistration.gateway_url}/runner/v1/releases/1.5.0/#{platform}", lines[0]
        assert_equal [ "aixle-runner configure --url #{Runners::MachineRegistration.gateway_url} --token arreg_t'ok --name build-01 --no-auto-update",
                       "aixle-runner service install", "aixle-runner service start" ], lines[1..]
        assert_not_includes output, "arreg_t'ok"
      end
    end
  end

  # runner-coder.md §8.2: the platform runs this script on a workspace it just
  # created, which has had no aixle-runner service. The script asks systemd
  # nothing itself (the binary's `service install` creates the unit), so a
  # machine with no earlier service gets the same three commands.
  test "it runs on a fresh machine with no earlier service" do
    pin(amd64: sha(BINARY))
    get "/runner/v1/machine-install.sh"

    Dir.mktmpdir do |dir|
      output, status, log = run_script(dir, "--token", "arreg_x", "--name", "fresh-vm", systemctl: :no_unit)

      assert status.success?, output
      assert_equal [ "aixle-runner configure --url #{Runners::MachineRegistration.gateway_url} --token arreg_x --name fresh-vm",
                     "aixle-runner service install", "aixle-runner service start" ], log.lines.map(&:chomp).grep(/\Aaixle-runner /)
      assert_not_includes output, "not found"
    end
  end

  test "it passes only the options it was given to configure" do
    pin(amd64: sha(BINARY))
    get "/runner/v1/machine-install.sh"

    Dir.mktmpdir do |dir|
      output, status, log = run_script(dir, "--token", "arreg_x")

      assert status.success?, output
      assert_includes log, "configure --url #{Runners::MachineRegistration.gateway_url} --token arreg_x\n"
    end
  end

  test "a digest mismatch runs nothing" do
    pin(amd64: "0" * 64)
    get "/runner/v1/machine-install.sh"

    Dir.mktmpdir do |dir|
      output, status, log = run_script(dir, "--token", "arreg_x", "--name", "m")

      assert_not status.success?
      assert_includes output, "does not match"
      assert_empty log.lines.grep(/\Aaixle-runner /)
    end
  end

  test "an unknown architecture is refused before any download" do
    pin(amd64: sha(BINARY))
    get "/runner/v1/machine-install.sh"

    Dir.mktmpdir do |dir|
      output, status, log = run_script(dir, "--token", "arreg_x", machine: "riscv64")

      assert_not status.success?
      assert_includes output, "unsupported architecture: riscv64"
      assert_equal "", log
    end
  end

  test "it refuses a machine that is not Linux, has no systemctl, or is not run as root" do
    pin(amd64: sha(BINARY))
    get "/runner/v1/machine-install.sh"

    { { kernel: "Darwin" } => "not running Linux", { systemctl: false } => "systemctl", { uid: "1000" } => "as root" }.each do |machine, message|
      Dir.mktmpdir do |dir|
        output, status, log = run_script(dir, "--token", "arreg_x", **machine)

        assert_not status.success?, machine.inspect
        assert_includes output, message
        assert_equal "", log
      end
    end
  end

  test "it accepts only --token, --name and --no-auto-update, and a plain name" do
    pin(amd64: sha(BINARY))
    get "/runner/v1/machine-install.sh"

    [ [ "--token", "t", "--url", "https://evil.example" ], [ "--token", "t", "extra" ], [ "--name", "m" ],
      [ "--token", "t", "--name", "a; rm -rf /" ], [ "--token", "t", "--name", "-x" ],
      [ "--token", "t", "--name", "a" * 64 ], [ "--token" ] ].each do |args|
      Dir.mktmpdir do |dir|
        output, status, log = run_script(dir, *args)

        assert_not status.success?, args.inspect
        assert_equal "", log, args.inspect
        assert_not_includes output, "evil.example"
      end
    end
  end
end
