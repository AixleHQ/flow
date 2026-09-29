# frozen_string_literal: true

require "test_helper"

# The living docs are read as a description of the code, and nothing else reads them
# back. Each test pins one kind of claim that has gone stale before to the code or the
# lockfile that decides it. Research reports, specs and strategy papers record what was
# true when they were written, so they are not checked.
class DocumentationDriftTest < ActiveSupport::TestCase
  TOP_LEVEL_DOCS = %w[ARCHITECTURE.md README.md CONTRIBUTING.md ROADMAP.md].freeze
  HISTORICAL_DIRS = %w[
    docs/research docs/implementation-artifacts docs/planning-artifacts docs/strategy docs/specs
  ].freeze
  RUNTIME_GUIDES = %w[docs/user-guide/runtimes.md app/frontend/pages/Docs/data/pages/runtimes.md].freeze

  NOT_IN_THE_APP = /\b(?:Rollbar|Redux|Zustand|ApplicationSerializer|ActiveModelSerializers|respond_with|InertiaPropsCamelizer)\b/i

  test "living docs name no library or class the app does not use" do
    hits = doc_lines.filter_map { |line, location| "#{location}: #{line.strip}" if line.match?(NOT_IN_THE_APP) }

    assert_empty hits, "Describe what the code uses instead — Sentry, Inertia props and React state, " \
                       "Alba resources, an explicit `render json:`, DeepKeyCamelizer:\n#{hits.join("\n")}"
  end

  test "the runtimes guide covers every runtime the app supports" do
    RUNTIME_GUIDES.each do |guide|
      text = Rails.root.join(guide).read
      missing = AgentCredentialsService.supported_agents.reject { |runtime| text.include?("`#{runtime}`") }

      assert_empty missing, "#{guide} does not describe #{missing.join(', ')}: add it to the runtime, " \
                            "credential and usage tables, in the docs/ copy and the portal copy alike"
    end
  end

  test "Ruby versions in the docs are the one .ruby-version pins" do
    pinned = Rails.root.join(".ruby-version").read.strip.delete_prefix("ruby-")
    wrong = version_mentions(/\bRuby (\d+\.\d+(?:\.\d+)?)\b/).reject do |version, _location|
      pinned == version || pinned.start_with?("#{version}.")
    end

    assert_empty wrong, "The app runs Ruby #{pinned} (.ruby-version). Update these, or drop the version " \
                        "and point at .ruby-version:\n#{wrong.map { |v, at| "#{at}: Ruby #{v}" }.join("\n")}"
  end

  test "Rails versions in the docs are the one Gemfile.lock locks" do
    lockfile = Bundler::LockfileParser.new(Rails.root.join("Gemfile.lock").read)
    locked = lockfile.specs.find { |spec| spec.name == "rails" }.version.segments.first(2).join(".")
    wrong = version_mentions(/\bRails (\d+\.\d+)/).reject { |version, _location| version == locked }

    assert_empty wrong, "Gemfile.lock locks Rails #{locked}. Update these, or drop the version and point " \
                        "at Gemfile.lock:\n#{wrong.map { |v, at| "#{at}: Rails #{v}" }.join("\n")}"
  end

  private

  def living_docs
    historical = HISTORICAL_DIRS.map { |dir| "#{Rails.root.join(dir)}/" }
    docs = Rails.root.glob("docs/**/*.md").reject { |path| path.to_s.start_with?(*historical) }

    TOP_LEVEL_DOCS.map { |name| Rails.root.join(name) } + docs
  end

  # [line, "path:number"] for every line of every living doc. `prose_only` skips fenced
  # code blocks, where a version is example data ("framework": "Rails 7.2") rather than
  # a claim about this app.
  def doc_lines(prose_only: false)
    living_docs.flat_map do |path|
      fenced = false
      path.each_line.with_index(1).filter_map do |line, number|
        fenced = !fenced if line.lstrip.start_with?("```")
        [ line, "#{path.relative_path_from(Rails.root)}:#{number}" ] unless prose_only && fenced
      end
    end
  end

  def version_mentions(pattern)
    doc_lines(prose_only: true).flat_map do |line, location|
      line.scan(pattern).map { |(version)| [ version, location ] }
    end
  end
end
