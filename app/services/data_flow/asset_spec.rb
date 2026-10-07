# frozen_string_literal: true

module DataFlow
  # One entry of a step's input_asset_specs or output_asset_specs, read the same
  # way by every check: the input and output validators, the skip evaluator and
  # DataFlow::Check.
  #
  # A name is a path relative to /workspace/outputs (an earlier session's file)
  # or an asset's name. Authors write the container path they read in the agent's
  # context, so a leading /workspace/assets/ or /workspace/outputs/ is dropped
  # rather than left to fail at run time. A name with *, ? or [ is a glob, where
  # `dir/**` takes everything under dir. `name_pattern` is the older regex form,
  # kept for the rows that use it.
  class AssetSpec
    GLOB = /[*?\[]/
    WORKSPACE_PREFIX = %r{\A/?workspace/(?:assets|outputs)/}
    FNMATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
    REGEXP_TIMEOUT = 0.1

    attr_reader :attributes, :name, :name_pattern

    # Specs have been stored in three shapes: the current array of hashes, hashes
    # without a "required" key (required), and — from an older builder — the
    # whole array JSON-encoded into a string.
    def self.list(value)
      value = parse_legacy(value) if value.is_a?(String)
      Array(value).filter_map do |entry|
        entry = { "name" => entry } if entry.is_a?(String)
        new(entry) if entry.is_a?(Hash)
      end
    end

    def self.normalize_name(name)
      name.to_s.strip.sub(WORKSPACE_PREFIX, "")
    end

    def self.parse_legacy(value)
      JSON.parse(value)
    rescue JSON::ParserError
      []
    end

    def initialize(attributes)
      @attributes = attributes.to_h.stringify_keys
      @name = self.class.normalize_name(@attributes["name"]).presence
      @name_pattern = @attributes["name_pattern"].presence
    end

    def required? = @attributes["required"] != false

    def glob? = name.present? && name.match?(GLOB)

    # A single file an author can point the agent at by path.
    def plain? = name.present? && !glob? && name_pattern.nil?

    def blank? = name.nil? && name_pattern.nil?

    def label = name || name_pattern

    def matches?(candidate)
      candidate = candidate.to_s
      if name_pattern
        regexp&.match?(candidate) || false
      elsif glob?
        File.fnmatch(name.sub(%r{/\*\*\z}, "/**/*"), candidate, FNMATCH_FLAGS)
      else
        name == candidate
      end
    rescue Regexp::TimeoutError
      false
    end

    # An author's regex runs on request threads (the builder's check), so a
    # catastrophic one is cut off instead of holding the thread.
    def regexp
      return @regexp if defined?(@regexp)

      @regexp = name_pattern && Regexp.new(name_pattern, timeout: REGEXP_TIMEOUT)
    rescue RegexpError
      @regexp = nil
    end

    def name_pattern_invalid? = name_pattern.present? && regexp.nil?

    # Why a name cannot match anything a session writes or an asset is called.
    def name_problem
      return nil if name.nil?
      return "is an absolute path" if name.start_with?("/", "~")
      return "leaves the workspace (..)" if name.split("/").include?("..")
      return "contains { or }" if name.match?(/[{}]/)

      nil
    end

    def to_h = @attributes.merge("name" => @attributes["name"].nil? ? nil : name).compact
  end
end
