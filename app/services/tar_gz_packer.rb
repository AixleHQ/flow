# frozen_string_literal: true

require "rubygems/package"
require "zlib"

# Packs a hash of { filename => content } into a tar.gz archive in memory.
class TarGzPacker
  def self.pack(files)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        files.each do |name, content|
          tar.add_file_simple(name.to_s, 0o644, content.bytesize) do |f|
            f.write(content)
          end
        end
      end
    end
    io.string
  end
end
