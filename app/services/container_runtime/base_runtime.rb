# frozen_string_literal: true

require "rubygems/package"
require "tempfile"

module ContainerRuntime
  # Abstract interface for container lifecycle and file operations.
  #
  # == Lifecycle
  #   pull_image(image)                          → Hash
  #   create_container(spec)                     → container handle
  #   start_container(id)                        → container handle
  #   wait_for_ready(id, ports=[])               → true
  #   stop_container(id, timeout=nil)            → void
  #   remove_container(id, options={})            → void
  #   remove_image(image)                        → void (no-op by default)
  #
  # == Execution
  #   exec(id, cmd, opts={})                     → [stdout_lines, stderr_lines, exit_code]
  #   exec!(id, cmd, opts={})                    → same, but raises ContainerUnreachableError
  #
  # == File I/O (tar-based, works on running containers)
  #   write_file(id, path, content, mode:, uid:, gid:) → true/false
  #   read_file(id, path)                              → String | nil
  #
  # == Introspection
  #   resolve_container(id)                      → container handle
  #   container_identifier(container)            → String
  #   container_status(id)                       → Symbol (see #container_status)
  #   wait_container(id, timeout=nil)            → Hash { "StatusCode" => int }
  #   container_logs(id, opts={})                → Hash { stdout:, stderr: }
  #
  # == Garbage collection
  #   list_session_resources                     → [ContainerRuntime::SessionResource]
  #   delete_session_resource(resource)          → true/false
  #
  class BaseRuntime
    # -- Lifecycle ------------------------------------------------------------

    def pull_image(_image)
      raise NotImplementedError, "#{self.class.name} must implement #pull_image"
    end

    def create_container(_spec)
      raise NotImplementedError, "#{self.class.name} must implement #create_container"
    end

    def start_container(_id)
      raise NotImplementedError, "#{self.class.name} must implement #start_container"
    end

    def wait_for_ready(_id, _ports = [])
      raise NotImplementedError, "#{self.class.name} must implement #wait_for_ready"
    end

    def stop_container(_id, _timeout = nil, _options = {})
      raise NotImplementedError, "#{self.class.name} must implement #stop_container"
    end

    def remove_container(_id, _options = {})
      raise NotImplementedError, "#{self.class.name} must implement #remove_container"
    end

    def remove_image(_image)
      # No-op by default; overridden in DockerRuntime.
    end

    # Resolve the pulled image's repo digest (for reproducibility pinning).
    # Returns a digest String or nil. Docker-specific; nil by default.
    def image_digest(_image)
      nil
    end

    # -- Execution ------------------------------------------------------------

    def exec(_id, _cmd, _opts = {})
      raise NotImplementedError, "#{self.class.name} must implement #exec"
    end

    # Same as #exec, but a container the runtime could not reach at all raises
    # ContainerUnreachableError instead of being flattened into an exit code of
    # 1 that is indistinguishable from a command that ran and failed. Callers
    # that must tell "the pod is gone" from "the command failed" use this.
    #
    # Runtimes that cannot tell the two apart answer exactly like #exec.
    def exec!(id, cmd, opts = {})
      exec(id, cmd, opts)
    end

    # -- File I/O -------------------------------------------------------------

    # Write a single file into the container via tar stream.
    # uid/gid are embedded in tar headers — no separate chown needed.
    def write_file(_id, _path, _content, mode: 0o644, uid: 0, gid: 0)
      raise NotImplementedError, "#{self.class.name} must implement #write_file"
    end

    # Read a single file from the container. Returns content string or nil.
    def read_file(_id, _path)
      raise NotImplementedError, "#{self.class.name} must implement #read_file"
    end

    # -- Introspection --------------------------------------------------------

    def resolve_container(_container_id)
      raise NotImplementedError, "#{self.class.name} must implement #resolve_container"
    end

    def container_identifier(_container)
      raise NotImplementedError, "#{self.class.name} must implement #container_identifier"
    end

    # Liveness of a container as the runtime sees it *right now*. One of:
    #
    #   :running    — the workload is up
    #   :starting   — accepted by the runtime but not up yet (k8s Pending,
    #                 docker "created"/"restarting") — NOT a dead container
    #   :terminated — it ran and is over (k8s Succeeded/Failed, docker exited/dead)
    #   :missing    — the runtime has no record of it at all
    #   :unknown    — the runtime could not answer (control-plane error, state
    #                 string we don't recognize)
    #
    # Callers may treat :terminated and :missing as "the agent is gone". They must
    # NOT treat :unknown that way: an unreachable control plane is not a dead pod,
    # and a scheduling backlog (:starting) is not one either.
    def container_status(_id)
      raise NotImplementedError, "#{self.class.name} must implement #container_status"
    end

    def wait_container(_id, _timeout = nil)
      raise NotImplementedError, "#{self.class.name} must implement #wait_container"
    end

    def container_logs(_id, _opts = {})
      raise NotImplementedError, "#{self.class.name} must implement #container_logs"
    end

    # -- Garbage collection ---------------------------------------------------
    #
    # A session's objects normally die in `remove_container`, which only runs on
    # the happy path. When the node holding an agent pod dies, that call never
    # happens and everything the session's routing was made of leaks — for
    # Kubernetes a Service with zero endpoints and the IngressRoute/Middlewares
    # pointing at it, which is why a dead session's URL answers with Traefik's
    # own "no available server" 503 instead of a terminal.
    #
    # These two primitives exist so a sweeper can reconcile what the runtime
    # actually holds against the `TerminalSession` rows that own it, without any
    # caller reaching into a vendor client (Kubeclient/Docker) itself.

    # Every session-scoped object this runtime currently holds, across every
    # namespace it manages.
    #
    # Implementations MUST return the objects in a safe deletion order — routing
    # objects before the workload they point at — so a caller can delete the
    # list front to back without ever leaving traffic aimed at a vanishing
    # backend. Implementations MUST NOT return shared infrastructure (a
    # namespace-wide auth middleware, the Traefik deployment, …): only objects
    # created for one session.
    #
    # @return [Array<ContainerRuntime::SessionResource>]
    def list_session_resources
      raise NotImplementedError, "#{self.class.name} must implement #list_session_resources"
    end

    # Deletes one object previously returned by #list_session_resources.
    # "Already gone" counts as success — the sweeper races real teardown by
    # design, and a 404 means the goal state was reached.
    #
    # @return [Boolean] true when the object is gone
    def delete_session_resource(_resource)
      raise NotImplementedError, "#{self.class.name} must implement #delete_session_resource"
    end

    private

    # -- Tar helpers (shared by Docker & Kubernetes implementations) ----------

    def build_tar_stream(path, content, mode: 0o644, uid: 0, gid: 0)
      normalized = normalize_tar_path(path)
      raise ArgumentError, "path is required" if normalized.blank?

      tar_io = Tempfile.new("aixle-tar")
      tar_io.binmode

      write_tar_entry(tar_io, normalized, content, mode: mode, uid: uid, gid: gid)
      write_tar_eof(tar_io)

      tar_io.rewind
      tar_io
    end

    # Both runtimes tar up ONE path per read_file, so the first regular-file entry
    # is the answer; `filename` is only a preference for a multi-entry tar, never a
    # filter. Filtering on it silently lost every file whose header name overflowed
    # tar's 100-byte name field: GNU/busybox tar (k8s `tar -cf -`, which tars the
    # full path) then emits a `././@LongLink` entry and truncates the real entry's
    # name, while Docker's Go writer emits a PAX `x` header and garbles it — either
    # way the basename stopped matching and read_file returned nil. Cyrillic names
    # (2 bytes/char) overflow at ~40 characters, so human-titled outputs vanished.
    def extract_from_tar(tar_data, filename = nil)
      first_file = nil

      io = StringIO.new(tar_data)
      Gem::Package::TarReader.new(io) do |tar|
        tar.each do |entry|
          # Long-name (`L`) and PAX (`x`, `g`) headers are metadata, not content.
          next unless entry.file?

          return entry.read if filename.present? && File.basename(entry.full_name) == filename

          first_file ||= entry.read
        end
      end

      first_file
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] extract_from_tar failed: #{e.message}")
      nil
    end

    def write_tar_entry(io, name, content, mode: 0o644, uid: 0, gid: 0)
      header = Gem::Package::TarHeader.new(
        name: name, mode: mode, size: content.bytesize,
        prefix: "", uid: uid, gid: gid, typeflag: "0", mtime: Time.now
      )
      io.write(header)
      io.write(content)
      remainder = (512 - (content.bytesize % 512)) % 512
      io.write("\0" * remainder) if remainder > 0
    end

    def write_tar_eof(io)
      io.write("\0" * 1024)
    end

    def normalize_tar_path(path)
      path.to_s.sub(%r{\A/}, "")
    end
  end
end
