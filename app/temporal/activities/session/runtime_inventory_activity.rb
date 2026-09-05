# frozen_string_literal: true

module Activities
  module Session
    # Reports what the container runtime currently holds.
    #
    # WHY THIS IS AN ACTIVITY: only the worker talks to the runtime. The web
    # process deliberately has no Docker socket (and should not: it is the
    # process exposed to HTTP, and the socket is root on the host), so the
    # cutover check and the admin's Enable button cannot look for themselves.
    # They ask the worker, which can.
    #
    # `strict: true` matters here: for a sweeper an unreadable runtime should
    # mean "delete nothing", but for an activation check it must mean "refuse",
    # so the error propagates instead of reading as an empty cluster.
    class RuntimeInventoryActivity < Base
      def run(_input = nil)
        resources = ContainerRuntime.build.list_session_resources(strict: true)
        {
          "runtime" => ContainerRuntime.build.class.name.demodulize,
          "resources" => resources.map { |r| "#{r.kind} #{r.namespace}/#{r.name}" }
        }
      end
    end
  end
end
