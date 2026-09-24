# frozen_string_literal: true

module Templates
  # A template as data: the parsed `template.yaml` plus the files next to it.
  # Built from the catalog mirror (Templates::CatalogSync) and from an export
  # (Templates::Exporter); read by the validator and the installer.
  class Package
    FORMAT_VERSION = 1
    SCHEMA_PATH = Rails.root.join("config/templates/template.v1.json")

    KINDS = %w[connector board workflow project].freeze
    DEFINITION_FILE = "template.yaml"
    README_FILE = "README.md"
    SETUP_FILE = "SETUP.md"

    attr_reader :definition, :files

    # @param definition [Hash] the parsed template.yaml, string keys
    # @param files [Hash{String => String}] package-relative path → raw bytes
    def initialize(definition:, files: {})
      @definition = definition.deep_stringify_keys
      @files = files.transform_keys(&:to_s)
    end

    def self.schema
      @schema ||= JSONSchemer.schema(JSON.parse(SCHEMA_PATH.read))
    end

    # @param yaml [String] the template.yaml text
    # @raise [Psych::Exception] on malformed YAML; aliases and non-plain types are refused
    def self.parse_definition(yaml)
      parsed = YAML.safe_load(yaml, permitted_classes: [], aliases: false)
      raise Psych::SyntaxError.new(DEFINITION_FILE, 0, 0, 0, "is not a mapping", "") unless parsed.is_a?(Hash)

      parsed
    end

    # Loads a package from an unpacked template directory (a checkout of the
    # templates repository, or a test fixture). Symlinks are not followed.
    def self.from_directory(dir)
      dir = Pathname(dir)
      files = Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).each_with_object({}) do |relative, acc|
        path = dir.join(relative)
        next if path.symlink? || !path.file? || relative == DEFINITION_FILE

        acc[relative] = path.binread
      end
      new(definition: parse_definition(dir.join(DEFINITION_FILE).read), files: files)
    end

    def slug = definition["slug"]
    def version = definition["version"]
    def name = definition["name"]

    def section(key) = Array(definition[key])

    def board = definition["board"]

    # Derived, not declared: the sections present decide what the template is.
    def kind
      if board && section("workflows").any? then "project"
      elsif section("workflows").any? then "workflow"
      elsif board then "board"
      else "connector"
      end
    end

    def inputs = section("inputs")
    def requires = definition["requires"] || {}
    def secrets = Array(requires["secrets"])
    def variables = section("variables")
    def config_item_names = (variables.pluck("name") + secrets.pluck("name")).uniq

    def readme = file(README_FILE)&.dup&.force_encoding(Encoding::UTF_8)
    def setup_markdown = file(SETUP_FILE)&.dup&.force_encoding(Encoding::UTF_8)

    def file(path) = files[path.to_s]

    def sha256(path) = Digest::SHA256.hexdigest(file(path).to_s)

    # Identity of what a person reviewed: definition + every file. Two packages
    # with the same digest install the same thing.
    # Keys are sorted recursively because jsonb does not keep key order, so the
    # mirrored copy must hash the same as the package it was built from.
    def digest
      payload = [ canonical(definition), files.sort.map { |path, bytes| [ path, Digest::SHA256.hexdigest(bytes) ] } ]
      Digest::SHA256.hexdigest(payload.to_json)
    end

    private

    def canonical(node)
      case node
      when Hash then node.sort_by { |key, _| key.to_s }.map { |key, value| [ key.to_s, canonical(value) ] }
      when Array then node.map { |value| canonical(value) }
      else node
      end
    end
  end
end
