# frozen_string_literal: true

require "test_helper"

class Runners::ConfigSchemaTest < ActiveSupport::TestCase
  def errors(config, type = "manual") = Runners::ConfigSchema.errors(config, type)

  test "a config that sets nothing is valid on manual, and every v1 key with a valid value passes" do
    assert_empty errors({})
    assert_empty errors(
      "reconnect_grace" => 120,
      "auto_update" => false,
      "container" => {
        "image_override" => "ghcr.io/acme/agent:1",
        "resources" => { "cpus" => 2, "memory" => "4g" },
        "workspace_volume" => false,
        "cache_mounts" => [ { "name" => "pip", "target" => "/home/agent/.cache/pip" } ],
        "home_mount" => { "path" => "/home/op", "writable" => false },
        "extra_mounts" => [ { "source" => "/srv/data", "target" => "/data" } ],
        "acknowledged_writable_mounts" => [],
        "network" => "host",
        "pid" => "private",
        "allow_privileged_mounts" => false,
        "docker_socket" => false
      }
    )
  end

  test "an unknown key is refused, at the top level and inside container" do
    assert_equal [ "colour is not a known setting" ], errors("colour" => "blue")
    assert_equal [ "container.gpu is not a known setting" ], errors("container" => { "gpu" => true })
  end

  test "a key of another type is refused with the types it applies to" do
    assert_equal [ "namespace applies only to kubernetes runners" ], errors("namespace" => "aixle")
    assert_equal [ "auto_update applies only to manual runners" ],
                 errors({ "template_id" => SecureRandom.uuid, "auto_update" => true }, "coder")
    assert_equal [ "container.docker_socket applies only to manual and coder runners" ],
                 errors({ "namespace" => "aixle", "container" => { "docker_socket" => true } }, "kubernetes")
  end

  test "a key that arrives later is refused as not supported yet" do
    assert_equal [ "execution_mode is not supported yet" ], errors("execution_mode" => "container")
    assert_equal [ "host.cli_source is not supported yet" ], errors("host" => { "cli_source" => "managed" })
  end

  test "ephemeral is refused as a per-machine registration setting" do
    assert_equal [ "ephemeral is not a config key: it is set per machine at registration" ], errors("ephemeral" => true)
  end

  test "values are checked against the key's type and range" do
    assert_equal [ "reconnect_grace must be between 60 and 7200" ], errors("reconnect_grace" => 30)
    assert_equal [ "reconnect_grace must be between 60 and 7200" ], errors("reconnect_grace" => 7201)
    assert_equal [ "reconnect_grace must be an integer" ], errors("reconnect_grace" => "900")
    assert_equal [ "container.extra_mounts[0].source must be an absolute path" ],
                 errors("container" => { "extra_mounts" => [ { "source" => "data", "target" => "/data" } ] })
    assert_equal [ "container.network must be one of bridge, host" ], errors("container" => { "network" => "none" })
    assert_equal [ "container.home_mount must be an object or null" ], errors("container" => { "home_mount" => "/home/op" })
    assert_equal [ "container.cache_mounts[0] must set exactly one of name or host_path" ],
                 errors("container" => { "cache_mounts" => [ { "target" => "/cache" } ] })
  end

  test "keys a type requires are required" do
    assert_equal [ "template_id is required" ], errors({}, "coder")
    assert_equal [ "namespace is required" ], errors({}, "kubernetes")
  end

  test "each type's schema declares only its own keys, with their defaults" do
    manual = Runners::ConfigSchema.for_type("manual")

    assert_equal false, manual["additionalProperties"] # rubocop:disable Minitest/RefuteFalse
    assert_equal 900, manual.dig("properties", "reconnect_grace", "default")
    assert_equal "bridge", manual.dig("properties", "container", "properties", "network", "default")
    assert_not manual["properties"].key?("namespace")
    assert_not manual["properties"].key?("execution_mode")
    assert_equal %w[image_override resources],
                 Runners::ConfigSchema.for_type("kubernetes").dig("properties", "container", "properties").keys
  end

  test "defaults are applied at read time and never written into config" do
    runner = create(:runner, :manual, config: { "container" => { "network" => "host" } })

    assert_equal({ "container" => { "network" => "host" } }, runner.reload.config)
    assert_equal 900, Runners::ConfigSchema.value(runner.config, "reconnect_grace")
    assert_equal "host", Runners::ConfigSchema.value(runner.config, "container.network")
    assert_equal "private", Runners::ConfigSchema.value(runner.config, "container.pid")
  end

  test "a runner whose config the schema refuses is invalid" do
    runner = build(:runner, :manual, config: { "namespace" => "aixle" })

    assert_not runner.valid?
    assert_includes runner.errors[:config], "namespace applies only to kubernetes runners"
  end
end
