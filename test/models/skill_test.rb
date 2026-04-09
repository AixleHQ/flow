# frozen_string_literal: true

require "test_helper"

class SkillTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  # ====== Validations ======

  test "valid skill with company scope" do
    skill = build(:skill, scope: @company)
    assert { skill.valid? }
  end

  test "valid skill with project scope" do
    skill = build(:skill, scope: @project)
    assert { skill.valid? }
  end

  test "name must be present" do
    skill = Skill.new(name: nil, scope: @company, title: "T", content: "C", package: "x/y@z", source: "x/y")
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  test "name must start with letter" do
    skill = build(:skill, name: "123invalid", scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  test "name allows hyphens" do
    skill = build(:skill, name: "my-skill", scope: @company)
    assert { skill.valid? }
  end

  test "name allows underscores" do
    skill = build(:skill, name: "my_skill", scope: @company)
    assert { skill.valid? }
  end

  test "name allows colons" do
    skill = build(:skill, name: "react:components", scope: @company)
    assert { skill.valid? }
  end

  test "name rejects uppercase (auto-downcased)" do
    skill = build(:skill, name: "MySkill", scope: @company)
    assert { skill.name == "myskill" }
    assert { skill.valid? }
  end

  test "name rejects special characters (auto-replaced)" do
    skill = build(:skill, name: "my skill!", scope: @company)
    assert { skill.name == "my_skill_" }
  end

  test "name must be unique within scope" do
    create(:skill, name: "duplicate", scope: @company)
    skill = build(:skill, name: "duplicate", scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:name].present? }
  end

  test "same name allowed in different scopes" do
    create(:skill, name: "shared-name", scope: @company)
    skill = build(:skill, name: "shared-name", scope: @project)
    assert { skill.valid? }
  end

  test "requires scope" do
    skill = build(:skill, scope: nil)
    assert { !skill.valid? }
    assert { skill.errors[:scope_type].present? }
  end

  test "requires package" do
    skill = build(:skill, package: nil, scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:package].present? }
  end

  test "requires source" do
    skill = build(:skill, source: nil, scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:source].present? }
  end

  test "requires content" do
    skill = build(:skill, content: nil, scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:content].present? }
  end

  # ====== Name Normalization ======

  test "name= downcases" do
    skill = Skill.new
    skill.name = "MySkill"
    assert { skill.name == "myskill" }
  end

  test "name= replaces spaces with underscores" do
    skill = Skill.new
    skill.name = "my skill"
    assert { skill.name == "my_skill" }
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

  test ".for_company returns company-scoped skills" do
    create(:skill, name: "company-skill", scope: @company)
    create(:skill, name: "project-skill", scope: @project)

    result = Skill.for_company(@company)
    assert { result.count == 1 }
    assert { result.first.name == "company-skill" }
  end

  test ".for_project returns project-scoped skills" do
    create(:skill, name: "company-skill", scope: @company)
    create(:skill, name: "project-skill", scope: @project)

    result = Skill.for_project(@project)
    assert { result.count == 1 }
    assert { result.first.name == "project-skill" }
  end

  # ====== visible_for_company ======

  test ".visible_for_company includes only company skills" do
    create(:skill, name: "b-company", scope: @company)
    create(:skill, name: "c-project", scope: @project)

    result = Skill.visible_for_company(@company)
    names = result.pluck(:name)

    assert_includes names, "b-company"
    refute_includes names, "c-project"
  end

  test ".visible_for_company excludes other company skills" do
    other_company = create(:company, email_domain: "other-visible.com")
    create(:skill, name: "other-skill", scope: other_company)
    create(:skill, name: "my-skill", scope: @company)

    result = Skill.visible_for_company(@company)
    names = result.pluck(:name)

    assert_includes names, "my-skill"
    refute_includes names, "other-skill"
  end

  test ".visible_for_company returns ActiveRecord::Relation" do
    result = Skill.visible_for_company(@company)
    assert { result.is_a?(ActiveRecord::Relation) }
  end

  # ====== visible_for_project ======

  test ".visible_for_project includes company and project skills" do
    create(:skill, name: "b-company", scope: @company)
    create(:skill, name: "c-project", scope: @project)

    result = Skill.visible_for_project(@project)
    names = result.pluck(:name)

    assert_includes names, "b-company"
    assert_includes names, "c-project"
  end

  test ".visible_for_project excludes other company and project skills" do
    other_company = create(:company, email_domain: "other-proj-visible.com")
    other_owner = create(:user, :employee, company: other_company)
    other_project = create(:project, company: other_company, owner: other_owner)

    create(:skill, name: "other-company-skill", scope: other_company)
    create(:skill, name: "other-project-skill", scope: other_project)

    result = Skill.visible_for_project(@project)
    names = result.pluck(:name)

    refute_includes names, "other-company-skill"
    refute_includes names, "other-project-skill"
  end

  test ".visible_for_project returns ActiveRecord::Relation" do
    result = Skill.visible_for_project(@project)
    assert { result.is_a?(ActiveRecord::Relation) }
  end

  # ====== scope_indicator ======

  test "#scope_indicator returns 'company' for company skill" do
    skill = build(:skill, name: "c-skill", scope: @company)
    assert_equal "company", skill.scope_indicator
  end

  test "#scope_indicator returns 'project' for project skill" do
    skill = build(:skill, name: "p-skill", scope: @project)
    assert_equal "project", skill.scope_indicator
  end

  # ====== Registry helpers ======

  test "#registry_url returns skills.sh URL" do
    skill = build(:skill, name: "mantine-form", source: "mantinedev/skills", scope: @company)
    assert_equal "https://skills.sh/mantinedev/skills/mantine-form", skill.registry_url
  end

  # ====== Associations ======

  test "company has_many skills" do
    skill = create(:skill, name: "assoc-test", scope: @company)
    assert { @company.skills.include?(skill) }
  end

  test "project has_many skills" do
    skill = create(:skill, name: "assoc-test", scope: @project)
    assert { @project.skills.include?(skill) }
  end

  test "destroying company destroys its skills" do
    company = create(:company, email_domain: "doomed-co.com")
    create(:skill, name: "doomed-skill", scope: company)

    assert_difference("Skill.count", -1) do
      company.destroy
    end
  end

  test "destroying project destroys its skills" do
    project = create(:project, company: @company, owner: @owner)
    create(:skill, name: "doomed-skill", scope: project)

    assert_difference("Skill.count", -1) do
      project.destroy
    end
  end
end
