# frozen_string_literal: true

require "rubygems/package"
require "zlib"

# Canonical fake for Templates::RepositoryClient. Never stub api.github.com or
# codeload.github.com outside that client's own contract test (docs/testing.md
# R3/R4); inject this instead:
#
#   repo = FakeTemplatesRepository.new
#   repo.add_template_dir(Rails.root.join("test/fixtures/files/templates/dev-team-sdlc"))  # → acme/dev-team-sdlc
#   Templates::CatalogSync.new(client: repo).call
#
# `commit!` moves the head to a new sha, the way a merge to main would.
class FakeTemplatesRepository
  attr_reader :head_sha, :tarball_requests

  # Registers the `acme` namespace (owner acme-bot) the fixtures publish under.
  DEFAULT_NAMESPACES = <<~YAML
    - name: acme
      display_name: Acme Corp
      verified: true
      owners: [acme-bot]
  YAML

  def initialize
    @files = { "namespaces.yaml" => DEFAULT_NAMESPACES }
    @tarball_requests = []
    commit!
  end

  def add_template_dir(dir, namespace: "acme", slug: File.basename(dir))
    Dir.glob("**/*", base: dir).each do |relative|
      path = File.join(dir, relative)
      @files["templates/#{namespace}/#{slug}/#{relative}"] = File.binread(path) if File.file?(path)
    end
    self
  end

  def put(path, bytes)
    @files[path] = bytes
    self
  end

  def remove_template(identifier)
    @files.reject! { |path, _| path.start_with?("templates/#{identifier}/") }
    self
  end

  def commit!
    @head_sha = SecureRandom.hex(20)
    self
  end

  def tarball(sha)
    @tarball_requests << sha
    self.class.gzip_tar(@files.transform_keys { |path| "flow-templates-#{sha}/#{path}" })
  end

  # Builds a .tar.gz from `path => bytes` (optionally `path => { symlink: target }`).
  def self.gzip_tar(entries)
    io = StringIO.new("".b)
    Zlib::GzipWriter.wrap(io) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        entries.each do |path, bytes|
          if bytes.is_a?(Hash)
            tar.add_symlink(path, bytes[:symlink], 0o777)
          else
            tar.add_file_simple(path, 0o644, bytes.bytesize) { |f| f.write(bytes) }
          end
        end
      end
    end
    io.string
  end
end
