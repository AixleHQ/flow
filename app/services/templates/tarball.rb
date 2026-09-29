# frozen_string_literal: true

require "rubygems/package"
require "zlib"

module Templates
  # Unpacks a GitHub repository tarball in memory into `path => bytes`, with the
  # top-level `<repo>-<sha>/` directory stripped. Only regular files are kept:
  # symlinks, devices and anything whose path escapes the root are skipped, and
  # size caps bound what one malicious or broken tarball can cost.
  module Tarball
    MAX_FILE_BYTES = 1.megabyte
    MAX_TOTAL_BYTES = 50.megabytes
    MAX_ENTRIES = 5_000

    TooLarge = Class.new(StandardError)

    module_function

    def extract(gzipped)
      files = {}
      total = 0
      Zlib::GzipReader.wrap(StringIO.new(gzipped)) do |gzip|
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each_with_index do |entry, index|
            raise TooLarge, "more than #{MAX_ENTRIES} entries" if index >= MAX_ENTRIES
            next unless entry.file?

            path = relative_path(entry.full_name)
            next if path.nil? || entry.header.size > MAX_FILE_BYTES

            total += entry.header.size
            raise TooLarge, "more than #{MAX_TOTAL_BYTES} bytes unpacked" if total > MAX_TOTAL_BYTES

            files[path] = entry.read.to_s.b
          end
        end
      end
      files
    end

    # "flow-templates-<sha>/templates/x/template.yaml" → "templates/x/template.yaml";
    # nil for anything absolute, empty or containing "..".
    def relative_path(full_name)
      _root, rest = full_name.split("/", 2)
      return nil if rest.blank? || rest.start_with?("/")
      return nil if rest.split("/").any? { |part| part == ".." || part.empty? }

      rest
    end
  end
end
