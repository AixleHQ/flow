# frozen_string_literal: true

require "test_helper"

class SkillTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  # ====== Validations ======

  test "company scope is rejected (skills are project-only)" do
    skill = build(:skill, scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:scope_type].include?("is not included in the list") }
  end

  test "valid skill with project scope" do
    skill = build(:skill, scope: @project)
    assert { skill.valid? }
  end

  test "name must be present" do
    skill = Skill.new(name: nil, scope: @project, title: "T", content: "C", package: "x/y@z", source: "x/y")
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  # Registry names are published by skills.sh and get passed verbatim to
  # `skills add --skill <name>`, so a digit-leading name has to be accepted —
  # they exist upstream (e.g. "3b1b-style-animation-skill").
  test "registry name may start with a digit" do
    skill = build(:skill, name: "3b1b-style-animation", scope: @project)
    assert { skill.valid? }
  end

  test "name rejects a leading hyphen" do
    skill = build(:skill, name: "-invalid", scope: @project)
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  test "name allows hyphens" do
    skill = build(:skill, name: "my-skill", scope: @project)
    assert { skill.valid? }
  end

  test "name allows underscores" do
    skill = build(:skill, name: "my_skill", scope: @project)
    assert { skill.valid? }
  end

  test "name allows colons" do
    skill = build(:skill, name: "react:components", scope: @project)
    assert { skill.valid? }
  end

  test "name rejects uppercase (auto-downcased)" do
    skill = build(:skill, name: "MySkill", scope: @project)
    assert { skill.name == "myskill" }
    assert { skill.valid? }
  end

  # The setter used to rewrite junk into underscores, which quietly produced a
  # name that no longer matched the skill it came from. It is now rejected.
  test "name rejects special characters instead of rewriting them" do
    skill = build(:skill, name: "my skill!", scope: @project)
    assert { skill.name == "my skill!" }
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  test "name is capped at the spec's 64 characters" do
    skill = build(:skill, name: "a" * 65, scope: @project)
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  test "name must be unique within scope" do
    create(:skill, name: "duplicate", scope: @project)
    skill = build(:skill, name: "duplicate", scope: @project)
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  test "same name allowed in different scopes" do
    project2 = create(:project, company: @company, owner: @owner)
    create(:skill, name: "shared-name", scope: @project)
    skill = build(:skill, name: "shared-name", scope: project2)
    assert { skill.valid? }
  end

  test "requires scope" do
    skill = build(:skill, scope: nil)
    assert { !skill.valid? }
    assert { skill.errors[:scope_type].present? }
  end

  test "requires package" do
    skill = build(:skill, package: nil, scope: @project)
    assert { !skill.valid? }
    assert { skill.errors[:package].present? }
  end

  test "requires source" do
    skill = build(:skill, source: nil, scope: @project)
    assert { !skill.valid? }
    assert { skill.errors[:source].present? }
  end

  test "requires content" do
    skill = build(:skill, content: nil, scope: @project)
    assert { !skill.valid? }
    assert { skill.errors[:content].present? }
  end

  # ====== Name Normalization ======

  test "name= downcases" do
    skill = Skill.new
    skill.name = "MySkill"
    assert { skill.name == "myskill" }
  end

  # The setter normalizes case and surrounding whitespace only. Anything else is
  # left intact so validation can reject it instead of silently renaming a skill.
  test "name= strips surrounding whitespace without rewriting the value" do
    skill = Skill.new
    skill.name = "  my skill  "
    assert { skill.name == "my skill" }
  end

  test "name= preserves hyphens" do
    skill = Skill.new
    skill.name = "my-skill"
    assert { skill.name == "my-skill" }
  end

  test "name= preserves colons" do
    skill = Skill.new
    skill.name = "react:components"
    assert { skill.name == "react:components" }
  end

  test "name= handles nil" do
    skill = Skill.new
    skill.name = nil
    assert { skill.name.nil? }
  end

  # ====== Scopes ======

  test ".for_project returns only that project's skills" do
    project2 = create(:project, company: @company, owner: @owner)
    create(:skill, name: "mine-skill", scope: @project)
    create(:skill, name: "other-skill", scope: project2)

    result = Skill.for_project(@project)
    assert { result.count == 1 }
    assert { result.first.name == "mine-skill" }
  end

  # ====== visible_for_project ======

  test ".visible_for_project includes only that project's skills" do
    project2 = create(:project, company: @company, owner: @owner)
    create(:skill, name: "mine-skill", scope: @project)
    create(:skill, name: "other-skill", scope: project2)

    result = Skill.visible_for_project(@project)
    names = result.pluck(:name)

    assert_includes names, "mine-skill"
    refute_includes names, "other-skill"
  end

  test ".visible_for_project excludes other project skills" do
    other_company = create(:company, email_domain: "other-proj-visible.com")
    other_owner = create(:user, :employee, company: other_company)
    other_project = create(:project, company: other_company, owner: other_owner)

    create(:skill, name: "other-project-skill", scope: other_project)
    create(:skill, name: "my-project-skill", scope: @project)

    result = Skill.visible_for_project(@project)
    names = result.pluck(:name)

    assert_includes names, "my-project-skill"
    refute_includes names, "other-project-skill"
  end

  test ".visible_for_project returns ActiveRecord::Relation" do
    result = Skill.visible_for_project(@project)
    assert { result.is_a?(ActiveRecord::Relation) }
  end

  # ====== scope_indicator ======

  test "#scope_indicator returns 'project' for project skill" do
    skill = build(:skill, name: "p-skill", scope: @project)
    assert_equal "project", skill.scope_indicator
  end

  # ====== Origin ======

  test "origin defaults to registry" do
    skill = build(:skill, scope: @project)
    assert_equal "registry", skill.origin
    assert { skill.registry? }
  end

  test "manual skill is valid without source or package" do
    skill = build(:skill, origin: :manual, source: nil, package: nil, name: "my-manual-skill", scope: @project)
    assert { skill.valid? }
  end

  test "registry skill still requires source and package" do
    skill = build(:skill, source: nil, package: nil, scope: @project)
    assert { !skill.valid? }
    assert { skill.errors[:source].present? }
    assert { skill.errors[:package].present? }
  end

  # A manual skill's name becomes its directory name in the container, and the
  # Agent Skills spec requires the two to match — so the spec's charset is
  # enforced here even though registry names are accepted as published.
  test "manual name rejects characters the Agent Skills spec forbids" do
    %w[my_skill react:components my--skill trailing-].each do |bad|
      skill = build(:skill, origin: :manual, source: nil, package: nil, name: bad, scope: @project)
      assert { !skill.valid? }
      assert { skill.errors[:name].present? }
    end
  end

  test "manual name accepts spec-shaped names" do
    skill = build(:skill, origin: :manual, source: nil, package: nil, name: "pdf-processing", scope: @project)
    assert { skill.valid? }
  end

  test "registry name still accepts underscores and colons published upstream" do
    %w[my_skill react:components].each do |upstream|
      skill = build(:skill, name: upstream, scope: @project)
      assert { skill.valid? }
    end
  end

  # ====== Registry helpers ======

  test "#registry_url returns skills.sh URL" do
    skill = build(:skill, name: "mantine-form", source: "mantinedev/skills", scope: @project)
    assert_equal "https://skills.sh/mantinedev/skills/mantine-form", skill.registry_url
  end

  test "#registry_url is nil for a manual skill" do
    skill = build(:skill, origin: :manual, source: nil, package: nil, name: "hand-written", scope: @project)
    assert_nil skill.registry_url
  end

  # ====== Associations ======

  test "project has_many skills" do
    skill = create(:skill, name: "assoc-test", scope: @project)
    assert { @project.skills.include?(skill) }
  end

  test "destroying project destroys its skills" do
    project = create(:project, company: @company, owner: @owner)
    create(:skill, name: "doomed-skill", scope: project)

    assert_difference("Skill.count", -1) do
      project.destroy
    end
  end
end
