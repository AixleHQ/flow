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
  #
  # == File I/O (tar-based, works on running containers)
  #   write_file(id, path, content, mode:, uid:, gid:) → true/false
  #   read_file(id, path)                              → String | nil
  #
  # == Introspection
  #   resolve_container(id)                      → container handle
  #   container_identifier(container)            → String
  #   wait_container(id, timeout=nil)            → Hash { "StatusCode" => int }
  #   container_logs(id, opts={})                → Hash { stdout:, stderr: }
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

    # -- Execution ------------------------------------------------------------

    def exec(_id, _cmd, _opts = {})
      raise NotImplementedError, "#{self.class.name} must implement #exec"
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

    def wait_container(_id, _timeout = nil)
      raise NotImplementedError, "#{self.class.name} must implement #wait_container"
    end

    def container_logs(_id, _opts = {})
      raise NotImplementedError, "#{self.class.name} must implement #container_logs"
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

    def extract_from_tar(tar_data, filename)
      io = StringIO.new(tar_data)
      Gem::Package::TarReader.new(io) do |tar|
        tar.each do |entry|
          return entry.read if entry.file? && File.basename(entry.full_name) == filename
        end
      end
      nil
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
