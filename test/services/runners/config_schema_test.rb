# frozen_string_literal: true

require "test_helper"

class Runners::ConfigSchemaTest < ActiveSupport::TestCase
  def errors(config, type = "manual") = Runners::ConfigSchema.errors(config, type)

  # The manual type's rules beyond its schema, which ConfigSchema.errors
  # returns once the schema passes.
  def manual_rules(container) = errors("container" => container)

  def patterns_in(node)
    case node
    when Hash then node.flat_map { |name, value| name == "pattern" ? [ value ] : patterns_in(value) }
    when Array then node.flat_map { |value| patterns_in(value) }
    else []
    end
  end

  test "a config that sets nothing is valid on manual, and every v1 key with a valid value passes" do
    assert_empty errors({})
    assert_empty errors(
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

  test "ephemeral and reconnect_grace are refused like any other unknown key" do
    assert_equal [ "ephemeral is not a known setting" ], errors("ephemeral" => true)
    assert_equal [ "reconnect_grace is not a known setting" ], errors("reconnect_grace" => 900)
  end

  test "values are checked against the key's type and range" do
    assert_equal [ "auto_update must be true or false" ], errors("auto_update" => "yes")
    assert_equal [ "container.extra_mounts[0].source must be an absolute path" ],
                 errors("container" => { "extra_mounts" => [ { "source" => "data", "target" => "/data" } ] })
    assert_equal [ "container.network must be one of bridge, host" ], errors("container" => { "network" => "none" })
    assert_equal [ "container.home_mount must be an object or null" ], errors("container" => { "home_mount" => "/home/op" })
    assert_equal [ "container.cache_mounts[0] must set exactly one of name or host_path" ],
                 errors("container" => { "cache_mounts" => [ { "target" => "/cache" } ] })
  end

  test "every pattern in every type's schema is an ECMA-262 regex, read as one on the server" do
    patterns = Runners::ConfigSchema.types.flat_map { |type| patterns_in(Runners::ConfigSchema.for_type(type)) }.uniq

    assert_not_empty patterns
    patterns.each do |pattern|
      assert_no_match(/\\[AzZhG]/, pattern, "#{pattern} uses a Ruby-only escape")
      assert_nothing_raised { JSONSchemer::EcmaRegexp.ruby_equivalent(pattern) }
    end
    assert_empty errors("container" => { "home_mount" => { "path" => "/home/op" } })
    assert_equal [ "container.home_mount.path must be an absolute path" ],
                 errors("container" => { "home_mount" => { "path" => "A/" } })
    assert_equal [ "container.home_mount.path must be an absolute path" ],
                 errors("container" => { "home_mount" => { "path" => "home\n/op" } })
    assert_equal [ "container.cache_mounts[0].name is not valid" ],
                 errors("container" => { "cache_mounts" => [ { "name" => "pip\n", "target" => "/cache" } ] })
  end

  test "image_override accepts {agent}, and refuses an unknown placeholder or a non-reference" do
    assert_empty errors("container" => { "image_override" => "ghcr.io/aixlehq/flow-{agent}:develop" })
    assert_empty errors("container" => { "image_override" => "registry.internal:5000/{agent}" })
    assert_match(/unknown placeholder \{model\}/, errors("container" => { "image_override" => "acme/{model}" }).sole)
    assert_match(/must be an image reference/, errors("container" => { "image_override" => "Acme/Flow-{agent}" }).sole)
    assert_match(/must be an image reference/, errors("container" => { "image_override" => "acme/{agent" }).sole)
  end

  test "image_override follows Docker: the first component is a registry only with a dot, a port or localhost" do
    %w[ghcr.io/acme/flow-{agent}:develop localhost:5000/flow-{agent} localhost/flow-{agent} acme/flow-{agent} flow-{agent}].each do |value|
      assert_empty errors("container" => { "image_override" => value }), value
    end
    %w[UPPER/flow-{agent}:x Acme/flow-{agent} ghcr.io/Acme/flow-{agent}].each do |value|
      assert_match(/must be an image reference/, errors("container" => { "image_override" => value }).sole, value)
    end
  end

  test "image_reference replaces {agent} and leaves a plain value as it is" do
    assert_equal "acme/flow-codex:1", Runners::ConfigSchema.image_reference("acme/flow-{agent}:1", "codex")
    assert_equal "acme/agent:1", Runners::ConfigSchema.image_reference("acme/agent:1", "codex")
  end

  test "keys a type requires are required" do
    assert_equal [ "template_id is required" ], errors({}, "coder")
    assert_equal [ "namespace is required" ], errors({}, "kubernetes")
  end

  test "each type's schema declares only its own keys, with their defaults" do
    manual = Runners::ConfigSchema.for_type("manual")

    assert_equal false, manual["additionalProperties"] # rubocop:disable Minitest/RefuteFalse
    assert manual.dig("properties", "auto_update", "default")
    assert_equal "bridge", manual.dig("properties", "container", "properties", "network", "default")
    assert_not manual["properties"].key?("namespace")
    assert_not manual["properties"].key?("execution_mode")
    assert_equal %w[image_override resources],
                 Runners::ConfigSchema.for_type("kubernetes").dig("properties", "container", "properties").keys
  end

  test "defaults are applied at read time and never written into config" do
    runner = create(:runner, :manual, config: { "container" => { "network" => "host" } })

    assert_equal({ "container" => { "network" => "host" } }, runner.reload.config)
    assert Runners::ConfigSchema.value(runner.config, "auto_update")
    assert_equal "host", Runners::ConfigSchema.value(runner.config, "container.network")
    assert_equal "private", Runners::ConfigSchema.value(runner.config, "container.pid")
  end

  test "a home mount needs the path of the home directory to mount" do
    assert_equal [ "container.home_mount.path is required on a manual runner" ], manual_rules("home_mount" => { "writable" => false })
    assert_empty manual_rules("home_mount" => { "path" => "/home/op" })
    assert_empty manual_rules("home_mount" => nil)
  end

  test "every writable host mount must be acknowledged by its target path" do
    container = {
      "home_mount" => { "path" => "/home/op", "writable" => true },
      "extra_mounts" => [ { "source" => "/srv/out", "target" => "/out", "writable" => true },
                          { "source" => "/srv/in", "target" => "/in" } ],
      "cache_mounts" => [ { "host_path" => "/var/cache/pip", "target" => "/cache/pip" },
                          { "name" => "npm", "target" => "/cache/npm" } ]
    }

    assert_equal %w[/home/op /out /cache/pip].map { |t| "container.acknowledged_writable_mounts must list #{t}: it is a writable host mount" },
                 manual_rules(container)
    assert_empty manual_rules(container.merge("acknowledged_writable_mounts" => %w[/home/op /out /cache/pip]))
  end

  test "the Docker socket needs privileged mounts allowed" do
    assert_equal [ "container.docker_socket requires container.allow_privileged_mounts: it gives the agent root on the machine" ],
                 manual_rules("docker_socket" => true)
    assert_empty manual_rules("docker_socket" => true, "allow_privileged_mounts" => true)
  end

  test "the type's rules run only once the schema passes, and only for their type" do
    assert_equal [ "container.home_mount.path must be an absolute path" ],
                 manual_rules("home_mount" => { "path" => "home", "writable" => true })
    coder = { "template_id" => SecureRandom.uuid,
              "container" => { "extra_mounts" => [ { "source" => "/a", "target" => "/b", "writable" => true } ] } }
    assert_empty errors(coder, "coder"), "a coder runner acknowledges no mounts"
  end

  test "writable_host_mounts lists the home mount by its path and the others by their target" do
    config = { "container" => {
      "home_mount" => { "path" => "/home/op", "writable" => true },
      "extra_mounts" => [ { "source" => "/srv/out", "target" => "/out", "writable" => true },
                          { "source" => "/srv/in", "target" => "/in" } ],
      "cache_mounts" => [ { "host_path" => "/var/cache/pip", "target" => "/cache/pip" }, { "name" => "npm", "target" => "/cache/npm" } ]
    } }

    assert_equal %w[/home/op /out /cache/pip], Runners::ConfigSchema.writable_host_mounts(config)
  end

  test "a runner whose config the schema refuses is invalid" do
    runner = build(:runner, :manual, config: { "namespace" => "aixle" })

    assert_not runner.valid?
    assert_includes runner.errors[:config], "namespace applies only to kubernetes runners"
  end
end
