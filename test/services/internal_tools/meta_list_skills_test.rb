# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaListSkillsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  test "lists project-scoped skills visible for the session's project" do
    first_skill = create(:skill, scope: @project, name: "first-skill",
      title: "First Skill", package: "acme/skills@first-skill", source: "acme/skills")
    second_skill = create(:skill, scope: @project, name: "second-skill",
      title: "Second Skill", package: "acme/skills@second-skill", source: "acme/skills")

    result = InternalTools::MetaListSkills.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal 2, data["skills_count"]
    assert_equal 2, data["skills"].size

    by_id = data["skills"].index_by { |s| s["id"] }
    assert_equal %w[id name title package source scope_type].sort, by_id.values.first.keys.sort

    first_payload = by_id[first_skill.id]
    assert_equal "first-skill", first_payload["name"]
    assert_equal "First Skill", first_payload["title"]
    assert_equal "acme/skills@first-skill", first_payload["package"]
    assert_equal "acme/skills", first_payload["source"]
    assert_equal "Project", first_payload["scope_type"]

    second_payload = by_id[second_skill.id]
    assert_equal "second-skill", second_payload["name"]
    assert_equal "Project", second_payload["scope_type"]
  end

  test "excludes skills scoped to other projects and other companies" do
    visible = create(:skill, scope: @project, name: "visible-skill")

    other_project = create(:project, company: @company, owner: @user)
    create(:skill, scope: other_project, name: "other-project-skill")

    other_company = create(:company)
    other_company_project = create(:project, company: other_company, owner: create(:user, company: other_company))
    create(:skill, scope: other_company_project, name: "other-company-skill")

    result = InternalTools::MetaListSkills.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])

    assert_equal 1, data["skills_count"]
    returned_ids = data["skills"].map { |s| s["id"] }
    assert_equal [ visible.id ], returned_ids
  end

  test "targets an explicit project_id over the session's project" do
    create(:skill, scope: @project, name: "session-project-skill")

    other_project = create(:project, company: @company, owner: @user)
    other_skill = create(:skill, scope: other_project, name: "explicit-project-skill")

    result = InternalTools::MetaListSkills.new(
      params: { project_id: other_project.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])

    returned_names = data["skills"].map { |s| s["name"] }
    assert_includes returned_names, "explicit-project-skill"
    assert_not_includes returned_names, "session-project-skill"
    assert_equal other_skill.id, data["skills"].detect { |s| s["name"] == "explicit-project-skill" }["id"]
  end

  test "returns an empty list when no skills are visible for the project" do
    result = InternalTools::MetaListSkills.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])

    assert_equal 0, data["skills_count"]
    assert_equal [], data["skills"]
  end
end
