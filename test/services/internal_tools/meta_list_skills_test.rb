# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaListSkillsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  test "lists project- and company-scoped skills visible for the session's project" do
    project_skill = create(:skill, scope: @project, name: "project-skill",
      title: "Project Skill", package: "acme/skills@project-skill", source: "acme/skills")
    company_skill = create(:skill, scope: @company, name: "company-skill",
      title: "Company Skill", package: "acme/skills@company-skill", source: "acme/skills")

    result = InternalTools::MetaListSkills.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal 2, data["skills_count"]
    assert_equal 2, data["skills"].size

    by_id = data["skills"].index_by { |s| s["id"] }
    assert_equal %w[id name title package source scope_type].sort, by_id.values.first.keys.sort

    proj_payload = by_id[project_skill.id]
    assert_equal "project-skill", proj_payload["name"]
    assert_equal "Project Skill", proj_payload["title"]
    assert_equal "acme/skills@project-skill", proj_payload["package"]
    assert_equal "acme/skills", proj_payload["source"]
    assert_equal "Project", proj_payload["scope_type"]

    company_payload = by_id[company_skill.id]
    assert_equal "company-skill", company_payload["name"]
    assert_equal "Company", company_payload["scope_type"]
  end

  test "excludes skills scoped to other projects and other companies" do
    visible = create(:skill, scope: @project, name: "visible-skill")

    other_project = create(:project, company: @company, owner: @user)
    create(:skill, scope: other_project, name: "other-project-skill")

    other_company = create(:company)
    create(:skill, scope: other_company, name: "other-company-skill")

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
