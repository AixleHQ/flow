# frozen_string_literal: true

require "test_helper"

class DataFlow::AssetSpecTest < ActiveSupport::TestCase
  test "reads the current shape, a spec without a required key, and the legacy JSON string" do
    current = DataFlow::AssetSpec.list([ { "name" => "a.md", "required" => false } ])
    keyless = DataFlow::AssetSpec.list([ { "name" => "a.md" } ])
    legacy = DataFlow::AssetSpec.list('[{"name":"plan/prd.md","description":"Required"}]')

    assert_equal false, current.first.required? # rubocop:disable Minitest/RefuteFalse
    assert keyless.first.required?
    assert_equal [ "plan/prd.md" ], legacy.map(&:name)
    assert_empty DataFlow::AssetSpec.list("not json")
    assert_empty DataFlow::AssetSpec.list([ 42, nil ])
  end

  test "drops the container prefix an author copied from the agent's context" do
    assert_equal "docs/brief.md", DataFlow::AssetSpec.new("name" => "/workspace/assets/docs/brief.md").name
    assert_equal "report.md", DataFlow::AssetSpec.new("name" => " /workspace/outputs/report.md ").name
    assert_equal "report.md", DataFlow::AssetSpec.new("name" => "workspace/outputs/report.md").name
    assert_equal "outputs/report.md", DataFlow::AssetSpec.new("name" => "outputs/report.md").name
  end

  test "matches an exact name, a glob, a directory glob and a legacy regex" do
    exact = DataFlow::AssetSpec.new("name" => "report.md")
    glob = DataFlow::AssetSpec.new("name" => "reports/*.md")
    tree = DataFlow::AssetSpec.new("name" => "analysis/**")
    regex = DataFlow::AssetSpec.new("name" => "ignored", "name_pattern" => "\\Atech_design")

    assert exact.matches?("report.md")
    refute exact.matches?("reports/report.md")
    assert glob.matches?("reports/weekly.md")
    refute glob.matches?("reports/2026/weekly.md")
    assert tree.matches?("analysis/domain.md")
    assert tree.matches?("analysis/deep/notes.md")
    refute tree.matches?("planning/prd.md")
    assert regex.matches?("tech_design.md")
    assert exact.plain?
    refute_predicate glob, :plain?
    refute_predicate regex, :plain?
  end

  test "names a problem only for names that can never match a workspace file" do
    assert_nil DataFlow::AssetSpec.new("name" => "intake/brief.md").name_problem
    assert_equal "is an absolute path", DataFlow::AssetSpec.new("name" => "/etc/hosts").name_problem
    assert_equal "leaves the workspace (..)", DataFlow::AssetSpec.new("name" => "../secrets.md").name_problem
    assert_equal "contains { or }", DataFlow::AssetSpec.new("name" => "{{date}}.md").name_problem
  end

  test "an invalid regex matches nothing and says so" do
    spec = DataFlow::AssetSpec.new("name_pattern" => "*.md")

    assert spec.name_pattern_invalid?
    refute spec.matches?("a.md")
  end
end
