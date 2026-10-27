# frozen_string_literal: true

require "test_helper"

class Runners::ManualAdapterTest < ActiveSupport::TestCase
  def validate(container) = Runners::ManualAdapter.new.validate_config(build(:runner, :manual, config: { "container" => container }))

  test "the registry hands out the manual adapter, and refuses the types that have none yet" do
    assert_instance_of Runners::ManualAdapter, Runners::Adapter.for(build(:runner, :manual))
    assert_equal %w[manual], Runners::Adapter.available_types

    %w[coder kubernetes].each do |type|
      error = assert_raises(Runners::Adapter::UnavailableType) { Runners::Adapter.for_type(type) }
      assert_match(/not available yet/, error.message)
    end
  end

  test "a manual runner can neither be provisioned nor rebuilt" do
    capabilities = Runners::ManualAdapter.new.capabilities(build(:runner, :manual))

    assert_equal({ provisionable: false, rebuildable: false }, capabilities.to_h)
  end

  test "a home mount needs the path of the home directory to mount" do
    assert_equal [ "container.home_mount.path is required on a manual runner" ], validate("home_mount" => { "writable" => false })
    assert_empty validate("home_mount" => { "path" => "/home/op" })
    assert_empty validate("home_mount" => nil)
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
                 validate(container)
    assert_empty validate(container.merge("acknowledged_writable_mounts" => %w[/home/op /out /cache/pip]))
  end

  test "the Docker socket needs privileged mounts allowed" do
    assert_equal [ "container.docker_socket requires container.allow_privileged_mounts: it gives the agent root on the machine" ],
                 validate("docker_socket" => true)
    assert_empty validate("docker_socket" => true, "allow_privileged_mounts" => true)
  end
end
