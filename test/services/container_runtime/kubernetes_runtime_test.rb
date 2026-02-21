# frozen_string_literal: true

require "test_helper"

module ContainerRuntime
  class KubernetesRuntimeTest < ActiveSupport::TestCase
    setup do
      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:debug)
      @runtime = KubernetesRuntime.new
    end

    test "pull_image raises when image blank" do
      assert_raises(ArgumentError) { @runtime.pull_image("") }
      assert_raises(ArgumentError) { @runtime.pull_image(nil) }
    end

    test "pull_image returns skipped (no-op for k8s)" do
      result = @runtime.pull_image("alpine:latest")

      assert_equal :skipped, result[:status]
      assert_equal "alpine:latest", result[:image]
      assert_equal 0, result[:duration_seconds]
    end

    test "resolve_container returns handle when given OpenStruct with pod_name" do
      handle = OpenStruct.new(pod_name: "my-pod", namespace: "default")

      result = @runtime.resolve_container(handle)

      assert_equal handle, result
    end

    test "resolve_container returns handle when given object with pod_name" do
      handle = Object.new
      handle.define_singleton_method(:pod_name) { "my-pod" }

      result = @runtime.resolve_container(handle)

      assert result.respond_to?(:pod_name)
      assert_equal "my-pod", result.pod_name
    end

    test "resolve_container builds handle from string id" do
      result = @runtime.resolve_container("palad-abc123")

      assert_equal "palad-abc123", result.pod_name
      assert result.namespace.present?
      assert_equal "main", result.container_name
    end

    test "container_identifier returns nil for blank" do
      assert_nil @runtime.container_identifier(nil)
      assert_nil @runtime.container_identifier("")
    end

    test "container_identifier returns string when given string" do
      assert_equal "abc123", @runtime.container_identifier("abc123")
    end

    test "container_identifier returns pod_name when handle has it" do
      handle = OpenStruct.new(pod_name: "my-pod-xyz")

      assert_equal "my-pod-xyz", @runtime.container_identifier(handle)
    end

    test "copy_from returns empty string when path blank" do
      assert_equal "", @runtime.copy_from("id", "")
      assert_equal "", @runtime.copy_from("id", nil)
    end

    test "copy_to returns false when path blank" do
      assert_equal false, @runtime.copy_to("id", "", "content")
      assert_equal false, @runtime.copy_to("id", nil, "content")
    end

    test "remove_image is no-op" do
      assert_nil @runtime.remove_image("alpine:latest")
    end

    test "create_container creates pod via core_client" do
      core_mock = mock("core_client")
      core_mock.expects(:create_pod).with do |pod|
        pod.kind == "Pod" &&
          pod.metadata[:name].present? &&
          pod.spec[:containers].first[:image] == "alpine:latest"
      end.returns(true)
      @runtime.stubs(:core_client).returns(core_mock)

      spec = {
        image: "alpine:latest",
        env_vars: [],
        labels: {},
        host_config: {}
      }

      result = @runtime.create_container(spec)

      assert result.pod_name.present?
      assert result.namespace.present?
    end

    test "stop_container deletes pod" do
      handle = OpenStruct.new(pod_name: "my-pod", namespace: "default")
      core_mock = mock("core_client")
      core_mock.expects(:delete_pod).with("my-pod", "default")

      @runtime.stubs(:core_client).returns(core_mock)

      @runtime.stop_container(handle)
    end

    test "start_container returns handle when no service ports" do
      handle = OpenStruct.new(
        pod_name: "my-pod",
        namespace: "default",
        service_ports: [],
        route_token: nil
      )

      result = @runtime.start_container(handle)

      assert_equal handle, result
    end
  end
end
