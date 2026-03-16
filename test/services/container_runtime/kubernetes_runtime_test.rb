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

    test "resolve_container preserves namespace from persisted identifier" do
      result = @runtime.resolve_container("palad-user-42/terminal-abc123")

      assert_equal "palad-user-42", result.namespace
      assert_equal "terminal-abc123", result.pod_name
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

    test "container_identifier includes namespace when handle has both namespace and pod_name" do
      handle = OpenStruct.new(namespace: "palad-project-7", pod_name: "my-pod-xyz")

      assert_equal "palad-project-7/my-pod-xyz", @runtime.container_identifier(handle)
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
      @runtime.stubs(:ensure_runtime_namespace_resources)
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

    test "create_container bootstraps isolated project namespace resources" do
      core_mock = mock("core_client")
      traefik_mock = mock("traefik_client")
      networking_mock = mock("networking_client")
      secret = Kubeclient::Resource.new(
        metadata: { name: "ghcr-pull-secret", namespace: "palad" },
        type: "kubernetes.io/dockerconfigjson",
        data: { ".dockerconfigjson" => "ZXhhbXBsZQ==" }
      )

      @runtime.stubs(:agents_image_pull_secrets).returns([ "ghcr-pull-secret" ])

      core_mock.expects(:get_namespace).with("palad-project-77").raises(StandardError)
      core_mock.expects(:create_namespace).with do |resource|
        resource.kind == "Namespace" &&
          resource.metadata[:name] == "palad-project-77" &&
          resource.metadata[:labels]["palad.ai/scope"] == "project"
      end.returns(true)
      core_mock.expects(:get_secret).with("ghcr-pull-secret", "palad-project-77").raises(StandardError)
      core_mock.expects(:get_secret).with("ghcr-pull-secret", "palad").returns(secret)
      core_mock.expects(:create_secret).with do |resource|
        metadata = resource.metadata.respond_to?(:to_h) ? resource.metadata.to_h : resource.metadata
        data = resource.data.respond_to?(:to_h) ? resource.data.to_h : resource.data

        resource.kind == "Secret" &&
          (metadata[:name] || metadata["name"]) == "ghcr-pull-secret" &&
          (metadata[:namespace] || metadata["namespace"]) == "palad-project-77" &&
          resource.type == "kubernetes.io/dockerconfigjson" &&
          (data[:".dockerconfigjson"] || data[".dockerconfigjson"]) == "ZXhhbXBsZQ=="
      end.returns(true)
      core_mock.expects(:create_pod).returns(true)
      core_mock.expects(:get_resource_quota).with("palad-resource-quota", "palad-project-77").raises(Kubeclient::ResourceNotFoundError.new(404, "Not Found", nil))
      core_mock.expects(:create_resource_quota).returns(true)

      traefik_mock.expects(:get_entity).with("middlewares", "terminal-auth", "palad-project-77").raises(StandardError)
      traefik_mock.expects(:create_entity).with do |kind, resource_type, resource|
        kind == "Middleware" &&
          resource_type == "middlewares" &&
          resource.kind == "Middleware" &&
          resource.metadata[:namespace] == "palad-project-77"
      end.returns(true)

      %w[
        runtime-default-deny
        runtime-allow-traefik-ingress
        runtime-allow-dns-egress
        runtime-allow-palad-service-egress
        runtime-allow-public-internet-egress
      ].each do |name|
        networking_mock.expects(:get_entity).with("networkpolicies", name, "palad-project-77").raises(StandardError)
      end
      5.times do
        networking_mock.expects(:create_entity).with do |kind, resource_type, resource|
          kind == "NetworkPolicy" &&
            resource_type == "networkpolicies" &&
            resource.is_a?(Kubeclient::Resource) &&
            resource.kind == "NetworkPolicy"
        end.returns(true)
      end

      @runtime.stubs(:core_client).returns(core_mock)
      @runtime.stubs(:traefik_client).returns(traefik_mock)
      @runtime.stubs(:networking_client).returns(networking_mock)

      result = @runtime.create_container(
        image: "alpine:latest",
        env_vars: [],
        labels: {},
        host_config: {},
        namespace_context: { project_id: 77, user_id: 5 }
      )

      assert_equal "palad-project-77", result.namespace
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

    test "create_ingressroute includes ide path with auth middleware only" do
      handle = OpenStruct.new(
        pod_name: "my-pod",
        namespace: "default",
        ingress_name: "my-pod-ingress",
        service_name: "my-pod",
        route_token: "abc123"
      )

      @runtime.stubs(:traefik_entrypoint).returns("websecure")
      @runtime.stubs(:traefik_auth_middleware).returns("terminal-auth")

      traefik_mock = mock("traefik_client")
      traefik_mock.expects(:create_entity).with do |kind, resource_type, ingress|
        spec = ingress.spec.respond_to?(:to_h) ? ingress.spec.to_h : ingress.spec
        routes = spec[:routes] || spec["routes"] || []
        ide_route = routes.find do |route|
          route_hash = route.respond_to?(:to_h) ? route.to_h : route
          match = route_hash[:match] || route_hash["match"]
          match.to_s.include?("/t/abc123/ide")
        end
        ide_route_hash = ide_route.respond_to?(:to_h) ? ide_route.to_h : ide_route
        middlewares = ide_route_hash && (ide_route_hash[:middlewares] || ide_route_hash["middlewares"])
        services = ide_route_hash && (ide_route_hash[:services] || ide_route_hash["services"])
        normalized_middlewares = Array(middlewares).map { |mw| mw.respond_to?(:to_h) ? mw.to_h : mw }
        normalized_services = Array(services).map { |svc| svc.respond_to?(:to_h) ? svc.to_h : svc }

        kind == "IngressRoute" &&
          resource_type == "ingressroutes" &&
          ingress.kind == "IngressRoute" &&
          routes.size == 3 &&
          ide_route.present? &&
          normalized_middlewares == [ { name: "terminal-auth" } ] &&
          normalized_services == [ { name: "my-pod", port: 8443 } ]
      end.returns(true)

      @runtime.stubs(:traefik_client).returns(traefik_mock)

      @runtime.send(:create_ingressroute, handle)
    end

    test "build_route includes host matcher from settings domain" do
      Settings.stubs(:domain).returns("palad.ai")
      handle = OpenStruct.new(route_token: "abc123", service_name: "svc")

      route = @runtime.send(:build_route, handle, "tty", 7681, [ "terminal-auth" ])

      assert_equal "Host(`palad.ai`) && PathPrefix(`/t/abc123/tty`)", route[:match]
    end

    test "build_route falls back to path matcher when settings domain blank" do
      Settings.stubs(:domain).returns("")
      handle = OpenStruct.new(route_token: "abc123", service_name: "svc")

      route = @runtime.send(:build_route, handle, "tty", 7681, [ "terminal-auth" ])

      assert_equal "PathPrefix(`/t/abc123/tty`)", route[:match]
    end
  end
end
