# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "socket"

module ContainerRuntime
  class KubernetesRuntimeTest < ActiveSupport::TestCase
    setup do
      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:debug)
      @runtime = KubernetesRuntime.new
    end

    # Kubeclient really does hand labels back symbol-keyed. Building a genuine
    # Kubeclient::Resource here is the point: a Hash stand-in would read fine
    # with string keys and hide exactly the bug these guard clauses had.
    def managed_namespace(scope: "project", origin: "aixle-prod")
      Kubeclient::Resource.new(
        metadata: {
          name: "aixle-prod-project-27",
          labels: { "aixle.com/runtime-origin" => origin, "aixle.com/scope" => scope }
        }
      )
    end

    def quota_resource(uid:)
      Kubeclient::Resource.new(metadata: { name: "aixle-resource-quota", namespace: "aixle-prod-project-27", uid: uid })
    end

    test "remove_managed_session_quota accepts a namespace Kubeclient labelled" do
      SessionAdmissionPolicy.stubs(:enabled?).returns(true)
      core = mock("core_client")
      core.expects(:get_namespace).with("aixle-prod-project-27").returns(managed_namespace)
      core.expects(:get_resource_quota).returns(quota_resource(uid: "uid-1"))
      core.expects(:delete_entity).never
      @runtime.stubs(:core_client).returns(core)
      @runtime.stubs(:runtime_namespace).returns("aixle-prod")

      quota = @runtime.remove_managed_session_quota(namespace: "aixle-prod-project-27", uid: "uid-1", dry_run: true)

      assert_equal "uid-1", quota.metadata.uid
    end

    test "remove_managed_session_quota refuses a namespace outside the managed scope" do
      SessionAdmissionPolicy.stubs(:enabled?).returns(true)
      core = mock("core_client")
      core.expects(:get_namespace).returns(managed_namespace(scope: "something-else"))
      core.expects(:delete_entity).never
      @runtime.stubs(:core_client).returns(core)
      @runtime.stubs(:runtime_namespace).returns("aixle-prod")

      assert_raises(RuntimeError) do
        @runtime.remove_managed_session_quota(namespace: "aixle-prod-project-27", uid: "uid-1")
      end
    end

    test "remove_managed_session_quota refuses when the quota has been replaced since the audit" do
      SessionAdmissionPolicy.stubs(:enabled?).returns(true)
      core = mock("core_client")
      core.expects(:get_namespace).returns(managed_namespace)
      core.expects(:get_resource_quota).returns(quota_resource(uid: "uid-new"))
      core.expects(:delete_entity).never
      @runtime.stubs(:core_client).returns(core)
      @runtime.stubs(:runtime_namespace).returns("aixle-prod")

      assert_raises(RuntimeError) do
        @runtime.remove_managed_session_quota(namespace: "aixle-prod-project-27", uid: "uid-reviewed")
      end
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

      assert_respond_to result, :pod_name
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
      refute @runtime.write_file("id", "", "content")
      refute @runtime.write_file("id", nil, "content")
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

    # The agent node group is opt-in. With nothing configured the emitted pod
    # spec must be exactly what it was before node-pool pinning existed — an
    # empty nodeSelector/tolerations pair, or one naming a node group a cluster
    # does not have, leaves every agent pod Pending.
    test "build_pod emits no nodeSelector or tolerations when no agent node pool is configured" do
      Settings.kubernetes.stubs(:agents_node_pool).returns([])
      Settings.kubernetes.stubs(:agents_image_pull_secrets).returns([])

      pod_spec = build_agent_pod_spec

      assert_equal %i[automountServiceAccountToken enableServiceLinks restartPolicy containers],
                   pod_spec.keys,
                   "unconfigured agent pod spec gained or lost a key"
      assert_not pod_spec.key?(:nodeSelector)
      assert_not pod_spec.key?(:tolerations)
    end

    test "build_pod pins agent pods to the configured node pool and tolerates its matching taint" do
      Settings.kubernetes.stubs(:agents_node_pool).returns([ "aixle.com/workload=agent:NoSchedule" ])

      pod_spec = build_agent_pod_spec
      node_selector = node_selector_from(pod_spec)
      tolerations = tolerations_from(pod_spec)

      assert_equal({ "aixle.com/workload" => "agent" }, node_selector)
      assert_equal [ { key: "aixle.com/workload", operator: "Equal", value: "agent", effect: "NoSchedule" } ],
                   tolerations
      # The selector and the toleration are two views of the same entry: a pod
      # that selects a taint it does not tolerate never schedules.
      assert_equal node_selector, tolerations.to_h { |toleration| [ toleration[:key].to_s, toleration[:value] ] }
    end

    test "build_pod defaults the toleration effect to NoSchedule and skips unparseable node pool entries" do
      Settings.kubernetes.stubs(:agents_node_pool).returns([ "aixle.com/workload=agent", "nonsense" ])

      pod_spec = build_agent_pod_spec

      assert_equal({ "aixle.com/workload" => "agent" }, node_selector_from(pod_spec))
      assert_equal [ { key: "aixle.com/workload", operator: "Equal", value: "agent", effect: "NoSchedule" } ],
                   tolerations_from(pod_spec)
    end

    test "build_pod leaves tool pods unpinned even when an agent node pool is configured" do
      Settings.kubernetes.stubs(:agents_node_pool).returns([ "aixle.com/workload=agent:NoSchedule" ])
      Settings.kubernetes.stubs(:agents_image_pull_secrets).returns([])

      # Tool containers are created without a container_name, so they get no
      # route token — the same discriminator the ingress path already uses.
      pod_spec = build_agent_pod_spec(container_name: nil)

      assert_equal %i[automountServiceAccountToken enableServiceLinks restartPolicy containers],
                   pod_spec.keys
      assert_not pod_spec.key?(:nodeSelector)
      assert_not pod_spec.key?(:tolerations)
    end

    # -- container_status: is this pod still alive? --
    #
    # Pods run with restartPolicy: Never and no owning controller, so a dead agent
    # either leaves a terminated pod behind or — when its node is gone — no pod at
    # all. Both must read as "gone"; a pod that has simply not been scheduled yet
    # must not.

    test "container_status reports a running pod as running" do
      stub_pod_phase("Running")

      assert_equal :running, @runtime.container_status(pod_handle)
    end

    test "container_status reports a pending pod as starting" do
      stub_pod_phase("Pending")

      assert_equal :starting, @runtime.container_status(pod_handle)
    end

    test "container_status reports a pod that left the Running phase as terminated" do
      stub_pod_phase("Failed")
      assert_equal :terminated, @runtime.container_status(pod_handle)

      stub_pod_phase("Succeeded")
      assert_equal :terminated, @runtime.container_status(pod_handle)
    end

    test "container_status reports a pod the API no longer knows as missing" do
      core_mock = mock("core_client")
      core_mock.stubs(:get_pod).raises(Kubeclient::ResourceNotFoundError.new(404, "pods 'my-pod' not found", nil))
      @runtime.stubs(:core_client).returns(core_mock)

      assert_equal :missing, @runtime.container_status(pod_handle)
    end

    test "container_status reports unknown rather than dead when the API cannot answer" do
      # An unreachable control plane is not a dead pod: callers only fail sessions
      # on :missing/:terminated.
      core_mock = mock("core_client")
      core_mock.stubs(:get_pod).raises(StandardError.new("connection refused"))
      @runtime.stubs(:core_client).returns(core_mock)

      assert_equal :unknown, @runtime.container_status(pod_handle)
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

    test "container_identifier truncates a raw container id to 12 chars" do
      container = Object.new
      container.define_singleton_method(:id) { "abcdef0123456789deadbeef" }

      assert_equal "abcdef012345", @runtime.container_identifier(container)
    end

    test "start_container creates only the service when handle has ports but no route token" do
      handle = OpenStruct.new(
        pod_name: "my-pod",
        namespace: "default",
        service_name: "my-pod",
        route_token: nil,
        service_ports: [ 7681 ]
      )

      core_mock = mock("core_client")
      created_service = nil
      core_mock.expects(:create_service).with do |service|
        created_service = service
        true
      end.returns(true)
      @runtime.stubs(:core_client).returns(core_mock)
      # traefik_client intentionally left unstubbed: a routed resource call would
      # blow up, proving the no-route-token branch skips ingress setup entirely.

      result = @runtime.start_container(handle)

      assert_equal handle, result
      metadata = created_service.metadata.respond_to?(:to_h) ? created_service.metadata.to_h : created_service.metadata
      assert_equal "my-pod", metadata[:name] || metadata["name"]
      assert_equal "default", metadata[:namespace] || metadata["namespace"]
    end

    test "start_container creates service, middlewares, and ingressroute for a routed handle" do
      handle = OpenStruct.new(
        pod_name: "my-pod",
        namespace: "default",
        container_name: "main",
        service_name: "my-pod",
        ingress_name: "my-pod-ingress",
        middleware_names: [ "my-pod-tty-strip", "my-pod-fs-strip" ],
        route_token: "abc123",
        service_ports: [ 7681, 4040 ]
      )

      created_service = nil
      core_mock = mock("core_client")
      core_mock.expects(:create_service).with do |service|
        created_service = service
        true
      end.returns(true)

      created_entities = []
      traefik_mock = mock("traefik_client")
      # Auth middleware already present in the namespace -> no create for it.
      traefik_mock.expects(:get_entity).with("middlewares", "terminal-auth", "default").returns(true)
      traefik_mock.expects(:create_entity).times(3).with do |kind, resource_type, resource|
        created_entities << [ kind, resource_type, resource ]
        true
      end.returns(true)

      @runtime.stubs(:core_client).returns(core_mock)
      @runtime.stubs(:traefik_client).returns(traefik_mock)

      result = @runtime.start_container(handle)

      assert_equal handle, result

      spec = created_service.spec.respond_to?(:to_h) ? created_service.spec.to_h : created_service.spec
      ports = Array(spec[:ports] || spec["ports"]).map { |port| port.respond_to?(:to_h) ? port.to_h : port }
      assert_equal [ 7681, 4040 ], ports.map { |port| port[:port] || port["port"] }
      assert_equal [ 7681, 4040 ], ports.map { |port| port[:targetPort] || port["targetPort"] }

      assert_equal [ "Middleware", "Middleware", "IngressRoute" ], created_entities.map(&:first)
      assert_equal [ "middlewares", "middlewares", "ingressroutes" ], created_entities.map { |entity| entity[1] }
    end

    test "remove_container tears down ingressroute, middlewares, service, and pod" do
      handle = OpenStruct.new(
        pod_name: "my-pod",
        namespace: "default",
        service_name: "my-pod",
        ingress_name: "my-pod-ingress",
        middleware_names: [ "my-pod-tty-strip", "my-pod-fs-strip" ]
      )

      traefik_mock = mock("traefik_client")
      traefik_mock.expects(:delete_entity).with("ingressroutes", "my-pod-ingress", "default")
      traefik_mock.expects(:delete_entity).with("middlewares", "my-pod-tty-strip", "default")
      traefik_mock.expects(:delete_entity).with("middlewares", "my-pod-fs-strip", "default")

      core_mock = mock("core_client")
      core_mock.expects(:delete_service).with("my-pod", "default")
      core_mock.expects(:delete_pod).with("my-pod", "default").returns(:pod_deleted)

      @runtime.stubs(:traefik_client).returns(traefik_mock)
      @runtime.stubs(:core_client).returns(core_mock)

      result = @runtime.remove_container(handle)

      assert_equal :pod_deleted, result
    end

    # -- Refused exec upgrade (pod gone) --------------------------------------

    test "handshake_status_code reads the HTTP status out of a refused upgrade" do
      handshake = ::WebSocket::Handshake::Client.new(url: "http://127.0.0.1:1/api/v1/pods/x/exec")

      begin
        handshake << "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n\r\n#{POD_NOT_FOUND_BODY}"
      rescue ::WebSocket::Error::Handshake::InvalidStatusCode
        # Whether the gem raises here depends on the global WebSocket.should_raise
        # flag; either way the raw response is now buffered on the handshake,
        # which is the only place the status code survives.
      end

      assert_equal 404, @runtime.send(:handshake_status_code, handshake)
    end

    test "handshake_status_code returns nil when there is nothing to read" do
      assert_nil @runtime.send(:handshake_status_code, nil)

      handshake = ::WebSocket::Handshake::Client.new(url: "http://127.0.0.1:1/api/v1/pods/x/exec")
      assert_nil @runtime.send(:handshake_status_code, handshake)
    end

    test "handshake_error? separates a refused upgrade from a mid-stream failure" do
      assert @runtime.send(:handshake_error?, ::WebSocket::Error::Handshake::InvalidStatusCode.new)
      assert_not @runtime.send(:handshake_error?, IOError.new("closed stream"))
      assert_not @runtime.send(:handshake_error?, "exec timeout after 30s")
    end

    test "exec logs the refused upgrade exactly once and reports a generic failure" do
      handle = OpenStruct.new(pod_name: "terminal-gone", namespace: "aixle-user-1", container_name: "main")

      logs = with_refused_exec_endpoint("404 Not Found") do
        stdout, stderr, exit_code = @runtime.exec(handle, [ "sh", "-c", "true" ], timeout: 5)

        assert_equal [], stdout
        assert_equal [], stderr
        assert_equal 1, exit_code
      end

      # The gem re-raises a failed handshake once per byte left in the HTTP
      # response (~190 lines for this body before the fix); the connection must
      # now be torn down after the first one.
      assert_equal 1, logs.scan("WebSocket handshake failed").size
      assert_equal 0, logs.scan("WebSocket error:").size
      assert_match(%r{aixle-user-1/terminal-gone is unreachable \(exec handshake returned HTTP 404\)}, logs)
    end

    test "exec! raises ContainerUnreachableError carrying the handshake status" do
      handle = OpenStruct.new(pod_name: "terminal-gone", namespace: "aixle-user-1", container_name: "main")

      error = nil
      logs = with_refused_exec_endpoint("404 Not Found") do
        error = assert_raises(ContainerRuntime::ContainerUnreachableError) do
          @runtime.exec!(handle, [ "sh", "-c", "true" ], timeout: 5)
        end
      end

      assert_equal 404, error.status_code
      assert_equal "aixle-user-1/terminal-gone", error.container_identifier
      assert_match(/unreachable/, error.message)
      assert_equal 1, logs.scan("WebSocket handshake failed").size
    end

    test "exec! reports the status of any refused upgrade, not just 404" do
      handle = OpenStruct.new(pod_name: "terminal-gone", namespace: "aixle-user-1", container_name: "main")

      error = nil
      with_refused_exec_endpoint("503 Service Unavailable") do
        error = assert_raises(ContainerRuntime::ContainerUnreachableError) do
          @runtime.exec!(handle, [ "sh", "-c", "true" ], timeout: 5)
        end
      end

      assert_equal 503, error.status_code
    end

    # == Session-object identity labels ==
    #
    # The garbage collector finds a dead session's objects by label, so every
    # object one session owns has to carry the same identity. Before this was
    # uniform only the Pod did, and a dead node's Service/IngressRoute could not
    # be attributed to anything.

    test "every object a session owns carries the same identity labels" do
      handle = OpenStruct.new(
        pod_name: "terminal-abc123",
        namespace: "aixle-project-7",
        container_name: "main",
        service_name: "terminal-abc123",
        ingress_name: "terminal-abc123-ingress",
        middleware_names: [ "terminal-abc123-tty-strip", "terminal-abc123-fs-strip" ],
        route_token: "abc123",
        service_ports: [ 7681, 4040 ]
      )

      created = []
      core_mock = mock("core_client")
      core_mock.expects(:create_service).with { |service| created << service }.returns(true)
      traefik_mock = mock("traefik_client")
      traefik_mock.expects(:get_entity).with("middlewares", "terminal-auth", "aixle-project-7").returns(true)
      traefik_mock.expects(:create_entity).times(3).with { |_kind, _plural, resource| created << resource }.returns(true)

      @runtime.stubs(:core_client).returns(core_mock)
      @runtime.stubs(:traefik_client).returns(traefik_mock)

      @runtime.start_container(handle)
      created << @runtime.send(:build_pod, { image: "alpine", env_vars: [] }, handle)

      assert_equal 5, created.size
      created.each do |resource|
        labels = labels_of(resource)
        assert_equal "aixle-runtime", labels["app"],
                     "#{resource.kind} is missing the runtime app label"
        assert_equal "terminal-abc123", labels["aixle-container"],
                     "#{resource.kind} is missing the per-session identity label"
      end
    end

    test "service selector stays the two pod identity labels so it keeps matching older pods" do
      handle = OpenStruct.new(
        pod_name: "terminal-abc123",
        namespace: "default",
        service_name: "terminal-abc123",
        route_token: nil,
        service_ports: [ 7681 ]
      )

      created_service = nil
      core_mock = mock("core_client")
      core_mock.expects(:create_service).with { |service| created_service = service }.returns(true)
      @runtime.stubs(:core_client).returns(core_mock)

      @runtime.start_container(handle)

      selector = created_service.spec.to_h[:selector].to_h.transform_keys(&:to_s)
      assert_equal({ "app" => "aixle-runtime", "aixle-container" => "terminal-abc123" }, selector)
    end

    test "the shared terminal-auth middleware carries no per-session label, so a sweep cannot select it" do
      middleware = @runtime.send(:build_terminal_auth_middleware, "aixle-project-7")

      labels = labels_of(middleware)
      assert_equal "aixle", labels["aixle.com/runtime-origin"]
      assert_not labels.key?("aixle-container")
    end

    # == Garbage-collection primitives ==

    test "list_session_resources maps labelled objects to session resources in deletion order" do
      core_mock = mock("core_client")
      traefik_mock = mock("traefik_client")

      traefik_mock.expects(:get_entities)
        .with("IngressRoute", "ingressroutes", label_selector: KubernetesRuntime::SESSION_RESOURCE_SELECTOR, as: :raw)
        .returns(items_json([ kube_item("terminal-abc123-ingress", "aixle-project-7", "terminal-abc123") ]))
      traefik_mock.expects(:get_entities)
        .with("Middleware", "middlewares", label_selector: KubernetesRuntime::SESSION_RESOURCE_SELECTOR, as: :raw)
        .returns(items_json([ kube_item("terminal-abc123-tty-strip", "aixle-project-7", "terminal-abc123") ]))
      core_mock.expects(:get_entities)
        .with("Service", "services", label_selector: KubernetesRuntime::SESSION_RESOURCE_SELECTOR, as: :raw)
        .returns(items_json([ kube_item("terminal-abc123", "aixle-project-7", "terminal-abc123") ]))
      core_mock.expects(:get_entities)
        .with("Pod", "pods", label_selector: KubernetesRuntime::SESSION_RESOURCE_SELECTOR, as: :raw)
        .returns(items_json([ kube_item("terminal-abc123", "aixle-project-7", "terminal-abc123") ]))

      @runtime.stubs(:core_client).returns(core_mock)
      @runtime.stubs(:traefik_client).returns(traefik_mock)

      resources = @runtime.list_session_resources

      assert_equal %w[IngressRoute Middleware Service Pod], resources.map(&:kind)
      assert_equal [ "abc123" ], resources.map(&:route_token).uniq
      assert_equal [ "aixle-project-7" ], resources.map(&:namespace).uniq
      assert_equal Time.zone.parse("2026-08-09T10:00:00Z"), resources.first.created_at
      assert_equal "terminal-abc123-ingress", resources.first.name
    end

    test "list_session_resources leaves the route token nil for a pod that is not an agent session" do
      resources = stub_listing([ kube_item("aixle-tool-xyz", "aixle", "aixle-tool-xyz") ])

      assert_nil resources.first.route_token
      assert_equal "aixle-tool-xyz", resources.first.name
    end

    test "list_session_resources reports nothing for a kind the API refuses to list" do
      core_mock = mock("core_client")
      traefik_mock = mock("traefik_client")
      traefik_mock.stubs(:get_entities).raises(StandardError.new("forbidden"))
      core_mock.stubs(:get_entities).raises(StandardError.new("forbidden"))
      @runtime.stubs(:core_client).returns(core_mock)
      @runtime.stubs(:traefik_client).returns(traefik_mock)

      assert_empty @runtime.list_session_resources
    end

    test "delete_session_resource routes each kind to its client and plural" do
      core_mock = mock("core_client")
      traefik_mock = mock("traefik_client")
      traefik_mock.expects(:delete_entity).with("ingressroutes", "terminal-abc123-ingress", "aixle-project-7")
      traefik_mock.expects(:delete_entity).with("middlewares", "terminal-abc123-tty-strip", "aixle-project-7")
      core_mock.expects(:delete_entity).with("services", "terminal-abc123", "aixle-project-7")
      core_mock.expects(:delete_entity).with("pods", "terminal-abc123", "aixle-project-7")
      @runtime.stubs(:core_client).returns(core_mock)
      @runtime.stubs(:traefik_client).returns(traefik_mock)

      names = {
        "IngressRoute" => "terminal-abc123-ingress",
        "Middleware" => "terminal-abc123-tty-strip",
        "Service" => "terminal-abc123",
        "Pod" => "terminal-abc123"
      }

      names.each do |kind, name|
        resource = SessionResource.new(kind: kind, name: name, namespace: "aixle-project-7", route_token: "abc123")
        assert @runtime.delete_session_resource(resource), "#{kind} should report deleted"
      end
    end

    test "delete_session_resource treats an already-gone object as success and a failure as false" do
      core_mock = mock("core_client")
      core_mock.expects(:delete_entity).with("pods", "gone", nil)
        .raises(Kubeclient::ResourceNotFoundError.new(404, "Not Found", nil))
      core_mock.expects(:delete_entity).with("pods", "broken", nil).raises(StandardError.new("boom"))
      @runtime.stubs(:core_client).returns(core_mock)

      assert @runtime.delete_session_resource(SessionResource.new(kind: "Pod", name: "gone"))
      assert_not @runtime.delete_session_resource(SessionResource.new(kind: "Pod", name: "broken"))
      assert_not @runtime.delete_session_resource(SessionResource.new(kind: "Pod", name: ""))
      assert_not @runtime.delete_session_resource(SessionResource.new(kind: "Namespace", name: "aixle"))
    end

    private

    # Builds the pod the way create_container does — real handle, real pod-spec
    # builder — and hands back the pod spec as a plain Hash. No API calls: only
    # settings are read on this path.
    def build_agent_pod_spec(container_name: "terminal-abc123")
      spec = {
        image: "alpine:latest",
        env_vars: [],
        labels: {},
        host_config: {},
        container_name: container_name
      }
      handle = @runtime.send(:build_handle, spec)
      pod = @runtime.send(:build_pod, spec, handle)

      pod.spec.respond_to?(:to_h) ? pod.spec.to_h : pod.spec
    end

    # Kubeclient::Resource symbolizes keys on the way in; normalize back so the
    # assertions read as the YAML Kubernetes actually receives.
    def node_selector_from(pod_spec)
      selector = pod_spec[:nodeSelector]
      selector = selector.to_h if selector.respond_to?(:to_h)
      selector.transform_keys(&:to_s)
    end

    def tolerations_from(pod_spec)
      Array(pod_spec[:tolerations]).map do |toleration|
        hash = toleration.respond_to?(:to_h) ? toleration.to_h : toleration
        hash.transform_keys(&:to_sym)
      end
    end

    # A resolved handle, so the status lookup is the only API call under test.
    def pod_handle
      OpenStruct.new(pod_name: "my-pod", namespace: "default")
    end

    def stub_pod_phase(phase)
      core_mock = mock("core_client")
      core_mock.stubs(:get_pod).with("my-pod", "default").returns(
        OpenStruct.new(status: OpenStruct.new(phase: phase))
      )
      @runtime.stubs(:core_client).returns(core_mock)
      core_mock
    end

    POD_NOT_FOUND_BODY = {
      kind: "Status",
      apiVersion: "v1",
      metadata: {},
      status: "Failure",
      message: 'pods "terminal-gone" not found',
      reason: "NotFound",
      details: { name: "terminal-gone", kind: "pods" },
      code: 404
    }.to_json.freeze

    # Stands in for the Kubernetes API server refusing the exec upgrade: a real
    # TCP listener answering with a non-101 status, driven through the real
    # websocket gem. Nothing vendor-owned is stubbed (docs/testing.md R2) — the
    # runtime's own k8s client is pointed at the listener instead.
    def with_refused_exec_endpoint(status_line)
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      acceptor = Thread.new do
        Thread.current.report_on_exception = false
        socket = server.accept
        loop do
          line = socket.gets
          break if line.nil? || line == "\r\n"
        end
        socket.write(
          "HTTP/1.1 #{status_line}\r\n" \
          "Content-Type: application/json\r\n" \
          "Content-Length: #{POD_NOT_FOUND_BODY.bytesize}\r\n" \
          "\r\n#{POD_NOT_FOUND_BODY}"
        )
        socket.flush
        # Hold the connection open so the client, not the server, decides when
        # the exchange ends — that is the behaviour under test.
        socket.read
      rescue StandardError
        nil # the client hung up; nothing left for this listener to do
      end

      @runtime.stubs(:core_client).returns(Kubeclient::Client.new("http://127.0.0.1:#{port}/api", "v1"))

      capture_rails_log { yield }
    ensure
      acceptor&.kill
      server&.close
    end

    def capture_rails_log
      buffer = StringIO.new
      previous = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(buffer)
      yield
      buffer.string
    ensure
      Rails.logger = previous
    end

    def labels_of(resource)
      (resource.metadata.to_h[:labels] || {}).to_h.transform_keys(&:to_s)
    end

    def stub_listing(items)
      core_mock = mock("core_client")
      traefik_mock = mock("traefik_client")
      traefik_mock.stubs(:get_entities).returns(items_json([]))
      core_mock.stubs(:get_entities).returns(items_json([]))
      core_mock.stubs(:get_entities)
        .with("Pod", "pods", label_selector: KubernetesRuntime::SESSION_RESOURCE_SELECTOR, as: :raw)
        .returns(items_json(items))
      @runtime.stubs(:core_client).returns(core_mock)
      @runtime.stubs(:traefik_client).returns(traefik_mock)

      @runtime.list_session_resources
    end

    def items_json(items)
      { "items" => items }.to_json
    end

    def kube_item(name, namespace, container_label)
      {
        "metadata" => {
          "name" => name,
          "namespace" => namespace,
          "creationTimestamp" => "2026-08-09T10:00:00Z",
          "labels" => { "app" => "aixle-runtime", "aixle-container" => container_label }
        }
      }
    end

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
