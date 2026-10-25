# frozen_string_literal: true

require "test_helper"

# config/feature_flags.yml against the code that reads it: every entry is valid,
# every declared flag is still read somewhere in app/ or lib/, and every flag the
# code checks is declared. Deliberately no check on dates: a release flag past
# its remove_by is listed by `bin/rails feature_flags:audit`, because a test that
# turns red on a calendar date breaks unrelated PRs.
class FeatureFlagsRegistryTest < ActiveSupport::TestCase
  # Matches FeatureFlags::Registry::KEY_FORMAT, so a misspelling with the right
  # shape is caught too.
  BACKEND_CHECK = /\bFeature\.(?:enabled\?|explain)\(\s*(?::|["'])([a-z][a-z0-9_]*)/
  FRONTEND_CHECK = /\buseFeatureFlag\(\s*["']([A-Za-z][A-Za-z0-9]*)["']/
  SOURCES = %w[app lib].freeze
  SOURCE_FILES = "**/*.{rb,rake,erb,ts,tsx}"
  # Tests are not readers: a flag only a test mentions is unused, and a test may
  # spell a name wrong on purpose.
  NOT_READERS = %r{(?:\.test\.tsx?\z|\Aapp/frontend/test/)}

  # Every problem the registry has against `files` (`{ path => source }`).
  class References
    def initialize(registry, files)
      @registry = registry
      @files = files.transform_values { |source| code_only(source) }
    end

    def problems = unreferenced + undeclared_backend + undeclared_frontend

    def unreferenced
      @registry.definitions.filter_map do |definition|
        names = [ definition.key.to_s ]
        names << definition.key.to_s.camelize(:lower) if definition.client?
        next if names.any? { |name| @files.values.any? { |source| source.match?(/\b#{Regexp.escape(name)}\b/) } }

        "#{definition.key} is declared but nothing in app/ or lib/ reads it: remove the entry, or the leftover check"
      end
    end

    def undeclared_backend
      checks(BACKEND_CHECK).reject { |key, _| @registry.declared?(key) }.map do |key, location|
        "#{location}: Feature checks #{key.inspect}, which config/feature_flags.yml does not declare"
      end
    end

    def undeclared_frontend
      # The `features` prop camelizes keys, so the frontend reads boardAiSummary.
      by_name = @registry.definitions.index_by { |definition| definition.key.to_s.camelize(:lower) }

      checks(FRONTEND_CHECK).filter_map do |name, location|
        definition = by_name[name]
        next if definition&.client?

        if definition
          "#{location}: useFeatureFlag reads #{name.inspect}, but #{definition.key} is not declared client: true"
        else
          "#{location}: useFeatureFlag reads #{name.inspect}, which no flag in config/feature_flags.yml camelizes to"
        end
      end
    end

    private

    def checks(pattern)
      @files.flat_map do |path, source|
        source.each_line.with_index(1).flat_map do |line, number|
          line.scan(pattern).map { |(name)| [ name, "#{path}:#{number}" ] }
        end
      end
    end

    # Comment lines blanked, keeping line numbers: usage examples in comments
    # (app/services/feature.rb) are not checks.
    def code_only(source)
      source.each_line.map { |line| line.lstrip.start_with?("#", "//", "/*", "*") ? "\n" : line }.join
    end
  end

  def shipped_registry = FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH)

  def readers
    SOURCES.flat_map { |dir| Rails.root.glob("#{dir}/#{SOURCE_FILES}") }.each_with_object({}) do |path, files|
      relative = path.relative_path_from(Rails.root).to_s
      files[relative] = path.read unless relative.match?(NOT_READERS)
    end
  end

  def example_registry = FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY)

  def problems(files, registry: example_registry) = References.new(registry, files).problems

  test "every entry of config/feature_flags.yml is valid" do
    assert_nothing_raised { shipped_registry }
  end

  test "every declared flag is read, and every flag read is declared" do
    problems = References.new(shipped_registry, readers).problems

    assert_empty problems, "config/feature_flags.yml and the code disagree " \
                           "(docs/architecture/feature-flags.md):\n#{problems.join("\n")}"
  end

  test "an invalid entry fails" do
    error = assert_raises(FeatureFlags::InvalidRegistry) do
      FeatureFlags::Registry.new({ "board_ai_summary" => { "description" => "AI summary panel.", "kind" => "release" } })
    end

    assert_match(/board_ai_summary: missing owner, scope, default/, error.message)
  end

  test "the examples pass when both flags are read" do
    assert_empty problems(
      "app/services/boards/summary.rb" => "Feature.enabled?(:board_ai_summary, company: company)\n",
      "app/services/coder/reaper.rb" => "return unless Feature.enabled?(:coder_reap)\n"
    )
  end

  test "a client flag read only by the frontend counts as read" do
    assert_empty problems(
      "app/frontend/pages/Board/Drawer.tsx" => "const on = useFeatureFlag('boardAiSummary');\n",
      "app/services/coder/reaper.rb" => "Feature.enabled?(:coder_reap)\n"
    )
  end

  test "a declared flag nothing reads fails" do
    assert_equal [ "coder_reap is declared but nothing in app/ or lib/ reads it: remove the entry, or the leftover check" ],
                 problems("app/services/boards/summary.rb" => "Feature.enabled?(:board_ai_summary, company: nil)\n")
  end

  test "a mention in a comment is not a read" do
    assert_includes problems(
      "app/services/boards/summary.rb" => "Feature.enabled?(:board_ai_summary, company: nil)\n",
      "app/services/feature.rb" => "#   Feature.enabled?(:coder_reap)\n#   Feature.enabled?(:board_ai_sumary)\n"
    ), "coder_reap is declared but nothing in app/ or lib/ reads it: remove the entry, or the leftover check"
  end

  test "a backend check of an undeclared flag fails" do
    assert_equal [ "app/services/boards/summary.rb:2: Feature checks \"board_ai_sumary\", which config/feature_flags.yml does not declare" ],
                 problems("app/services/boards/summary.rb" => "Feature.enabled?(:board_ai_summary, company: nil)\n" \
                                                              "Feature.explain(:board_ai_sumary, company: nil)\n",
                          "app/services/coder/reaper.rb" => "Feature.enabled?(\"coder_reap\")\n")
  end

  test "a frontend read of an undeclared or non-client flag fails" do
    found = problems(
      "app/services/boards/summary.rb" => "Feature.enabled?(:board_ai_summary, company: nil)\n",
      "app/services/coder/reaper.rb" => "Feature.enabled?(:coder_reap)\n",
      "app/frontend/pages/Board/Drawer.tsx" => "useFeatureFlag('boardAiSumary');\nuseFeatureFlag(\"coderReap\");\n"
    )

    assert_equal [ "app/frontend/pages/Board/Drawer.tsx:1: useFeatureFlag reads \"boardAiSumary\", which no flag in config/feature_flags.yml camelizes to",
                   "app/frontend/pages/Board/Drawer.tsx:2: useFeatureFlag reads \"coderReap\", but coder_reap is not declared client: true" ],
                 found
  end

  test "test files are not readers" do
    assert_not readers.keys.any? { |path| path.end_with?(".test.ts", ".test.tsx") }
    assert readers.key?("app/services/feature.rb")
  end
end
