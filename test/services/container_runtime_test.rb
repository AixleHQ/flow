# frozen_string_literal: true

require "test_helper"

class ContainerRuntimeTest < ActiveSupport::TestCase
  test "build returns KubernetesRuntime when name is k8s" do
    runtime = ContainerRuntime.build("k8s")

    assert_instance_of ContainerRuntime::KubernetesRuntime, runtime
  end

  test "build returns KubernetesRuntime when name is kubernetes" do
    runtime = ContainerRuntime.build("kubernetes")

    assert_instance_of ContainerRuntime::KubernetesRuntime, runtime
  end

  test "build returns DockerRuntime when name is docker" do
    runtime = ContainerRuntime.build("docker")

    assert_instance_of ContainerRuntime::DockerRuntime, runtime
  end

  test "build returns DockerRuntime when name is empty or nil" do
    ContainerRuntime.stubs(:from_settings).returns("docker")

    assert_instance_of ContainerRuntime::DockerRuntime, ContainerRuntime.build("")
    assert_instance_of ContainerRuntime::DockerRuntime, ContainerRuntime.build(nil)
  end

  test "build uses from_settings when name is blank" do
    ContainerRuntime.stubs(:from_settings).returns("kubernetes")

    runtime = ContainerRuntime.build("   ")

    assert_instance_of ContainerRuntime::KubernetesRuntime, runtime
  end

  test "from_settings returns Settings.container_runtime when defined" do
    Settings.stubs(:container_runtime).returns("kubernetes")

    assert_equal "kubernetes", ContainerRuntime.from_settings
  end
end
