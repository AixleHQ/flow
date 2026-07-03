# frozen_string_literal: true

require "test_helper"
require "rubygems/package"

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
      result = @runtime.resolve_container("aixle-abc123")

      assert_equal "aixle-abc123", result.pod_name
      assert result.namespace.present?
      assert_equal "main", result.container_name
    end

    test "resolve_container preserves namespace from persisted identifier" do
      result = @runtime.resolve_container("aixle-user-42/terminal-abc123")

      assert_equal "aixle-user-42", result.namespace
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
      handle = OpenStruct.new(namespace: "aixle-project-7", pod_name: "my-pod-xyz")

      assert_equal "aixle-project-7/my-pod-xyz", @runtime.container_identifier(handle)
    end

    test "write_file returns false when path blank" do
      assert_equal false, @runtime.write_file("id", "", "content")
      assert_equal false, @runtime.write_file("id", nil, "content")
    end

    test "read_file returns nil when path blank" do
      assert_nil @runtime.read_file("id", "")
      assert_nil @runtime.read_file("id", nil)
    end

    test "read_file returns nil when copy_from yields empty archive" do
      @runtime.expects(:copy_from).with("ns/pod", "/workspace/note.txt").returns("")

      assert_nil @runtime.read_file("ns/pod", "/workspace/note.txt")
    end

    test "read_file extracts file matching basename from tar returned by copy_from" do
      tar_io = Tempfile.new("k8s-read-file")
      tar_io.binmode
      Gem::Package::TarWriter.new(tar_io) do |tar|
        tar.add_file_simple("workspace/note.txt", 0o644, 9) { |io| io.write("file body") }
      end
      tar_io.rewind
      tar_bytes = tar_io.read
      tar_io.close!

      @runtime.expects(:copy_from).with("handle", "/workspace/note.txt").returns(tar_bytes)

      assert_equal "file body", @runtime.read_file("handle", "/workspace/note.txt")
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
        metadata: { name: "ghcr-pull-secret", namespace: "aixle" },
        type: "kubernetes.io/dockerconfigjson",
        data: { ".dockerconfigjson" => "ZXhhbXBsZQ==" }
      )

      @runtime.stubs(:agents_image_pull_secrets).returns([ "ghcr-pull-secret" ])

      core_mock.expects(:get_namespace).with("aixle-project-77").raises(StandardError)
      core_mock.expects(:create_namespace).with do |resource|
        resource.kind == "Namespace" &&
          resource.metadata[:name] == "aixle-project-77" &&
          resource.metadata[:labels]["aixle.com/scope"] == "project"
      end.returns(true)
      core_mock.expects(:get_secret).with("ghcr-pull-secret", "aixle-project-77").raises(StandardError)
      core_mock.expects(:get_secret).with("ghcr-pull-secret", "aixle").returns(secret)
      core_mock.expects(:create_secret).with do |resource|
        metadata = resource.metadata.respond_to?(:to_h) ? resource.metadata.to_h : resource.metadata
        data = resource.data.respond_to?(:to_h) ? resource.data.to_h : resource.data

        resource.kind == "Secret" &&
          (metadata[:name] || metadata["name"]) == "ghcr-pull-secret" &&
          (metadata[:namespace] || metadata["namespace"]) == "aixle-project-77" &&
          resource.type == "kubernetes.io/dockerconfigjson" &&
          (data[:".dockerconfigjson"] || data[".dockerconfigjson"]) == "ZXhhbXBsZQ=="
      end.returns(true)
      core_mock.expects(:create_pod).returns(true)
      core_mock.expects(:get_resource_quota).with("aixle-resource-quota", "aixle-project-77").raises(Kubeclient::ResourceNotFoundError.new(404, "Not Found", nil))
      core_mock.expects(:create_resource_quota).returns(true)

      traefik_mock.expects(:get_entity).with("middlewares", "terminal-auth", "aixle-project-77").raises(StandardError)
      traefik_mock.expects(:create_entity).with do |kind, resource_type, resource|
        kind == "Middleware" &&
          resource_type == "middlewares" &&
          resource.kind == "Middleware" &&
          resource.metadata[:namespace] == "aixle-project-77" &&
          resource.metadata[:labels]["aixle.com/runtime-origin"] == "aixle"
      end.returns(true)

      %w[
        runtime-default-deny
        runtime-allow-traefik-ingress
        runtime-allow-dns-egress
        runtime-allow-aixle-service-egress
        runtime-allow-public-internet-egress
      ].each do |name|
        networking_mock.expects(:get_entity).with("networkpolicies", name, "aixle-project-77").raises(StandardError)
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

      assert_equal "aixle-project-77", result.namespace
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
        metadata = ingress.metadata.respond_to?(:to_h) ? ingress.metadata.to_h : ingress.metadata
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
          (metadata[:namespace] || metadata["namespace"]) == "default" &&
          (metadata.dig(:labels, :"aixle.com/runtime-origin") || metadata.dig("labels", "aixle.com/runtime-origin")) == "aixle" &&
          routes.size == 3 &&
          ide_route.present? &&
          normalized_middlewares == [ { name: "terminal-auth" } ] &&
          normalized_services == [ { name: "my-pod", namespace: "default", port: 8443 } ]
      end.returns(true)

      @runtime.stubs(:traefik_client).returns(traefik_mock)

      @runtime.send(:create_ingressroute, handle)
    end

    test "build_route includes host matcher from settings domain" do
      Settings.stubs(:domain).returns("aixle.com")
      handle = OpenStruct.new(route_token: "abc123", service_name: "svc")

      route = @runtime.send(:build_route, handle, "tty", 7681, [ "terminal-auth" ])

      assert_equal "Host(`aixle.com`) && PathPrefix(`/t/abc123/tty`)", route[:match]
    end

    test "build_route falls back to path matcher when settings domain blank" do
      Settings.stubs(:domain).returns("")
      handle = OpenStruct.new(route_token: "abc123", service_name: "svc")

      route = @runtime.send(:build_route, handle, "tty", 7681, [ "terminal-auth" ])

      assert_equal "PathPrefix(`/t/abc123/tty`)", route[:match]
    end

    test "resource_labels include runtime origin and namespace when provided" do
      @runtime.stubs(:runtime_namespace).returns("aixle-staging")
      labels = @runtime.send(:resource_labels, namespace: "aixle-staging-project-1")

      assert_equal "aixle-staging", labels["aixle.com/runtime-origin"]
      assert_equal "aixle-staging-project-1", labels["aixle.com/runtime-namespace"]
    end

    test "build_quota_hard_limits uses settings project_defaults when no db record" do
      project_defaults = OpenStruct.new(
        cpu_requests: nil,
        memory_requests: nil,
        cpu_limits: "2000m",
        memory_limits: "4Gi",
        max_pods: 50
      )
      ns_quota_settings = OpenStruct.new(project_defaults: project_defaults, user_defaults: OpenStruct.new(cpu_requests: nil, memory_requests: nil, cpu_limits: nil, memory_limits: nil, max_pods: nil))
      Settings.stubs(:namespace_resource_quotas).returns(ns_quota_settings)

      hard = @runtime.send(:build_quota_hard_limits, nil, "Project")

      assert_equal "2000m", hard["limits.cpu"]
      assert_equal "4Gi",   hard["limits.memory"]
      assert_equal "50",    hard["count/pods"]
      assert_not hard.key?("requests.cpu")
      assert_not hard.key?("requests.memory")
    end

    test "build_quota_hard_limits db record values override settings defaults" do
      project_defaults = OpenStruct.new(
        cpu_requests: nil,
        memory_requests: nil,
        cpu_limits: "2000m",
        memory_limits: "4Gi",
        max_pods: 50
      )
      ns_quota_settings = OpenStruct.new(project_defaults: project_defaults, user_defaults: OpenStruct.new(cpu_requests: nil, memory_requests: nil, cpu_limits: nil, memory_limits: nil, max_pods: nil))
      Settings.stubs(:namespace_resource_quotas).returns(ns_quota_settings)

      record = NamespaceResourceQuota.new(cpu_limits: "8000m", memory_limits: nil, max_pods: nil)

      hard = @runtime.send(:build_quota_hard_limits, record, "Project")

      assert_equal "8000m", hard["limits.cpu"]
      assert_equal "4Gi",   hard["limits.memory"]
      assert_equal "50",    hard["count/pods"]
    end

    test "build_quota_hard_limits returns empty hash when all settings and record values are nil" do
      empty_defaults = OpenStruct.new(cpu_requests: nil, memory_requests: nil, cpu_limits: nil, memory_limits: nil, max_pods: nil)
      ns_quota_settings = OpenStruct.new(project_defaults: empty_defaults, user_defaults: empty_defaults)
      Settings.stubs(:namespace_resource_quotas).returns(ns_quota_settings)

      hard = @runtime.send(:build_quota_hard_limits, nil, "Project")

      assert_empty hard
    end

    test "build_quota_hard_limits uses user_defaults for User scope" do
      user_defaults = OpenStruct.new(
        cpu_requests: nil,
        memory_requests: nil,
        cpu_limits: "1000m",
        memory_limits: "2Gi",
        max_pods: 20
      )
      project_defaults = OpenStruct.new(cpu_requests: nil, memory_requests: nil, cpu_limits: "4000m", memory_limits: "8Gi", max_pods: 100)
      ns_quota_settings = OpenStruct.new(project_defaults: project_defaults, user_defaults: user_defaults)
      Settings.stubs(:namespace_resource_quotas).returns(ns_quota_settings)

      hard = @runtime.send(:build_quota_hard_limits, nil, "User")

      assert_equal "1000m", hard["limits.cpu"]
      assert_equal "2Gi",   hard["limits.memory"]
      assert_equal "20",    hard["count/pods"]
    end
    private

    def build_test_tar(filename, content)
      io = StringIO.new
      io.binmode
      Gem::Package::TarWriter.new(io) do |tar|
        tar.add_file_simple(filename, 0o644, content.bytesize) { |f| f.write(content) }
      end
      io.string
    end
  end
end
