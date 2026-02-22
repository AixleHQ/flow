# frozen_string_literal: true

require "test_helper"

class SkillTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  # ====== Validations ======

  test "valid custom skill with company scope" do
    skill = build(:skill, scope: @company)
    assert { skill.valid? }
  end

  test "valid custom skill with project scope" do
    skill = build(:skill, scope: @project)
    assert { skill.valid? }
  end

  test "valid internal skill without scope" do
    skill = build(:skill, :internal, name: "internal-skill")
    assert { skill.valid? }
  end

  test "name must be present" do
    skill = Skill.new(name: nil, kind: "custom", scope: @company, title: "T", content: "C")
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

  test "custom skill requires scope_type" do
    skill = build(:skill, scope: nil)
    assert { !skill.valid? }
    assert { skill.errors[:scope_type].present? }
  end

  test "custom skill requires scope_id" do
    skill = Skill.new(name: "test", kind: "custom", scope_type: "Company", scope_id: nil, title: "T", content: "C")
    assert { !skill.valid? }
    assert { skill.errors[:scope_id].present? }
  end

  test "custom skill requires title" do
    skill = build(:skill, title: nil, scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:title].present? }
  end

  test "custom skill requires content" do
    skill = build(:skill, content: nil, scope: @company)
    assert { !skill.valid? }
    assert { skill.errors[:content].present? }
  end

  test "internal skill does not require title" do
    skill = build(:skill, :internal, name: "i-skill")
    assert { skill.valid? }
  end

  test "internal skill does not require content" do
    skill = build(:skill, :internal, name: "i-skill-2")
    assert { skill.valid? }
  end

  test "internal skill does not require scope" do
    skill = build(:skill, :internal, name: "i-skill-3")
    assert { skill.scope.nil? }
    assert { skill.valid? }
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

  test "name= handles nil" do
    skill = Skill.new
    skill.name = nil
    assert { skill.name.nil? }
  end

  # ====== Kind Helpers ======

  test "#internal? returns true for internal kind" do
    skill = build(:skill, :internal, name: "i-test")
    assert { skill.internal? }
  end

  test "#custom? returns true for custom kind" do
    skill = build(:skill, scope: @company)
    assert { skill.custom? }
  end

  # ====== Scopes ======

  test ".internal_skills returns only internal" do
    create(:skill, :internal, name: "internal-a")
    create(:skill, name: "custom-a", scope: @company)

    result = Skill.internal_skills
    assert { result.all?(&:internal?) }
    assert { result.count == 1 }
  end

  test ".custom_skills returns only custom" do
    create(:skill, :internal, name: "internal-b")
    create(:skill, name: "custom-b", scope: @company)

    result = Skill.custom_skills
    assert { result.all?(&:custom?) }
    assert { result.count == 1 }
  end

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

  test ".visible_for_company includes internal and company skills" do
    create(:skill, :internal, name: "a-internal")
    create(:skill, name: "b-company", scope: @company)
    create(:skill, name: "c-project", scope: @project)

    result = Skill.visible_for_company(@company)
    names = result.pluck(:name)

    assert_includes names, "a-internal"
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

  test ".visible_for_project includes internal, company, and project skills" do
    create(:skill, :internal, name: "a-internal")
    create(:skill, name: "b-company", scope: @company)
    create(:skill, name: "c-project", scope: @project)

    result = Skill.visible_for_project(@project)
    names = result.pluck(:name)

    assert_includes names, "a-internal"
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

  # ====== merged_for_project ======

  test ".merged_for_project includes internal, company, and project skills" do
    create(:skill, :internal, name: "a-internal")
    create(:skill, name: "b-company", scope: @company)
    create(:skill, name: "c-project", scope: @project)

    result = Skill.merged_for_project(@project)
    names = result.map(&:name)

    assert { names.include?("a-internal") }
    assert { names.include?("b-company") }
    assert { names.include?("c-project") }
  end

  test ".merged_for_project sets correct scope_indicators" do
    create(:skill, :internal, name: "a-internal")
    create(:skill, name: "b-company", scope: @company)
    create(:skill, name: "c-project", scope: @project)

    result = Skill.merged_for_project(@project)

    internal = result.find { |s| s.name == "a-internal" }
    company = result.find { |s| s.name == "b-company" }
    project = result.find { |s| s.name == "c-project" }

    assert { internal.scope_indicator == "internal" }
    assert { company.scope_indicator == "company" }
    assert { project.scope_indicator == "project" }
  end

  test ".merged_for_project project overrides company with same name" do
    create(:skill, name: "shared-skill", scope: @company)
    create(:skill, name: "shared-skill", scope: @project)

    result = Skill.merged_for_project(@project)
    shared = result.select { |s| s.name == "shared-skill" }

    assert { shared.count == 1 }
    assert { shared.first.scope_indicator == "overrides_company" }
    assert { shared.first.scope_type == "Project" }
  end

  test ".merged_for_project excludes other company skills" do
    other_company = create(:company, email_domain: "other-skills.com")
    create(:skill, name: "other-company-skill", scope: other_company)

    result = Skill.merged_for_project(@project)
    names = result.map(&:name)

    assert { !names.include?("other-company-skill") }
  end

  test ".merged_for_project returns sorted by name" do
    create(:skill, name: "z-skill", scope: @company)
    create(:skill, :internal, name: "a-skill")
    create(:skill, name: "m-skill", scope: @project)

    result = Skill.merged_for_project(@project)
    assert { result.map(&:name) == result.map(&:name).sort }
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
