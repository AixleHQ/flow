# frozen_string_literal: true

require "rubygems/package"
require "tempfile"

module ContainerRuntime
  # BaseRuntime
  # Abstract interface for container lifecycle operations.
  class BaseRuntime
    def pull_image(_image)
      raise NotImplementedError, "#{self.class.name} must implement #pull_image"
    end

    def create_container(_spec)
      raise NotImplementedError, "#{self.class.name} must implement #create_container"
    end

    def start_container(_id)
      raise NotImplementedError, "#{self.class.name} must implement #start_container"
    end

    def exec(_id, _cmd, _opts = {})
      raise NotImplementedError, "#{self.class.name} must implement #exec"
    end

    def copy_from(_id, _path)
      raise NotImplementedError, "#{self.class.name} must implement #copy_from"
    end

    def copy_to(_id, _path, _content)
      raise NotImplementedError, "#{self.class.name} must implement #copy_to"
    end

    def stop_container(_id, _timeout = nil, _options = {})
      raise NotImplementedError, "#{self.class.name} must implement #stop_container"
    end

    def remove_container(_id, _options = {})
      raise NotImplementedError, "#{self.class.name} must implement #remove_container"
    end

    def remove_image(_image)
      # Optional no-op by default.
    end

    def wait_for_ready(_id, _ports = [])
      raise NotImplementedError, "#{self.class.name} must implement #wait_for_ready"
    end

    def resolve_container(container_id)
      raise NotImplementedError, "#{self.class.name} must implement #resolve_container"
    end

    def container_identifier(_container)
      raise NotImplementedError, "#{self.class.name} must implement #container_identifier"
    end

    private

    def build_tar_stream(path, content)
      normalized = normalize_tar_path(path)
      raise ArgumentError, "path is required" if normalized.blank?

      tar_io = Tempfile.new("palad-copy-to")
      tar_io.binmode

      Gem::Package::TarWriter.new(tar_io) do |tar|
        tar.add_file_simple(normalized, 0o644, content.bytesize) do |io|
          io.write(content)
        end
      end

      tar_io.rewind
      tar_io
    end

    def normalize_tar_path(path)
      path.to_s.sub(%r{\A/}, "")
    end
  end
end
