# frozen_string_literal: true

module ContainerStrategies
  # DSL-based strategy for internal container tools.
  # Each tool is registered via `define :name { ... }` with declarative configuration.
  # New tools can be added in ~15 lines instead of ~200.
  class InternalToolStrategy < ToolStrategy
    # --- DSL Definition ---

    class Definition
      attr_reader :name, :opts

      def initialize(name)
        @name = name
        @opts = {
          timeout: 300, memory: 1.gigabyte, cpu_quota: 50_000,
          working_dir: "/workspace", docker_socket: false,
          output_files: []
        }
      end

      def image(v)         = tap { @opts[:image] = v }
      def timeout(v)       = tap { @opts[:timeout] = v }
      def memory(v)        = tap { @opts[:memory] = v }
      def cpu_quota(v)     = tap { @opts[:cpu_quota] = v }
      def working_dir(v)   = tap { @opts[:working_dir] = v }
      def docker_socket!   = tap { @opts[:docker_socket] = true }
      def output_files(v)  = tap { @opts[:output_files] = v }

      def cmd(&block)      = tap { @opts[:cmd] = block }
      def env(&block)      = tap { @opts[:env] = block }
      def binds(&block)    = tap { @opts[:binds] = block }
      def prepare(&block)  = tap { @opts[:prepare] = block }
    end

    # --- Registry ---

    class << self
      def registry
        @registry ||= {}
      end

      def registered?(name)
        registry.key?(name.to_s)
      end

      def define(name, &block)
        defn = Definition.new(name)
        defn.instance_eval(&block)
        registry[name.to_s] = defn
      end

      def build_for(name, params:, session:, tool_result_id:, timeout: nil)
        defn = registry[name.to_s]
        raise ArgumentError, "No internal tool definition: #{name}" unless defn

        prepared = run_prepare(defn, params, session)
        new(prepared.merge(
          definition: defn,
          tool_result_id: tool_result_id,
          timeout: timeout || defn.opts[:timeout]
        ))
      end

      private

      def run_prepare(defn, params, session)
        base = (params || {}).symbolize_keys.merge(session: session)
        prep = defn.opts[:prepare]
        prep ? prep.call(base).symbolize_keys : base
      end
    end

    # --- Tool Definitions ---

    # --- Phase overrides ---

    def resolve_image = defn.opts[:image]
    def build_working_dir = defn.opts[:working_dir]
    def build_cmd = resolve_callable(defn.opts[:cmd])

    def build_env_vars
      hash = resolve_callable(defn.opts[:env]) || {}
      super + hash.map { |k, v| "#{k}=#{v}" }
    end

    def build_labels
      { "aixle.type" => "internal_tool", "aixle.tool" => defn.name.to_s }
    end

    def build_host_config
      cfg = defn.opts
      hc = base_host_config.merge(
        "Memory" => cfg[:memory], "MemorySwap" => cfg[:memory],
        "CpuPeriod" => 100_000, "CpuQuota" => cfg[:cpu_quota]
      )
      binds_val = resolve_callable(cfg[:binds]) || []
      if cfg[:docker_socket]
        binds_val << "/var/run/docker.sock:/var/run/docker.sock"
        binds_val.uniq!
      end
      hc["Binds"] = binds_val if binds_val.any?
      hc
    end

    def before_cleanup(container_id: nil, **)
      paths = defn.opts[:output_files]
      return {} if paths.blank? || container_id.blank?

      container = resolve_container(container_id)
      tr = ToolResult.find(input[:tool_result_id])
      tr.attach_output_files(container, paths, runtime)
      {}
    end

    private

    def defn = input[:definition]

    def exec_timeout
      defn.opts[:timeout]
    end

    def resolve_callable(val)
      val.is_a?(Proc) ? val.call(input) : val
    end
  end
end
