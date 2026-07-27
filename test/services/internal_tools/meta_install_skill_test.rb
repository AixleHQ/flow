# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaInstallSkillTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    # Builder workflow context (simulates Aixle Builder running the tool)
    builder_workflow = create(:workflow, scope: @project)
    builder_step = create(:step, workflow: builder_workflow)
    @workflow_run = create(:workflow_run, workflow: builder_workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: builder_step)

    step_run = @step_run
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }

    @api_key = "sk_live_test_key"
    Settings.skills_sh.api_key = @api_key
    @skill_id = "vercel-labs/agent-skills/next-js-development"
  end

  teardown do
    Settings.skills_sh.api_key = nil
  end

  def stub_detail_endpoint(skill_id: @skill_id, source: "vercel-labs/agent-skills", slug: "next-js-development", installs: 24_531)
    stub_request(:get, "https://skills.sh/api/v1/skills/#{skill_id}")
      .with(headers: { "Authorization" => "Bearer #{@api_key}" })
      .to_return(
        status: 200,
        body: {
          id: skill_id,
          source: source,
          slug: slug,
          installs: installs,
          files: [
            {
              path: "SKILL.md",
              contents: "---\nname: Next.js Development\ndescription: Build Next.js apps\n---\n\n# Next.js"
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "installs a skill into the given project scope and returns its payload" do
    stub_detail_endpoint

    result = InternalTools::MetaInstallSkill.new(
      params: { skill_id: @skill_id, scope_type: "Project", scope_id: @project.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]

    data = JSON.parse(result[:stdout])
    assert_equal "next-js-development", data["name"]
    assert_equal "Next.js Development", data["title"]
    assert_equal "vercel-labs/agent-skills@next-js-development", data["package"]
    assert_equal "vercel-labs/agent-skills", data["source"]

    skill = Skill.find(data["id"])
    assert skill.valid?, skill.errors.full_messages.to_sentence
    assert_equal "Project", skill.scope_type
    assert_equal @project.id, skill.scope_id
    assert_equal "vercel-labs/agent-skills@next-js-development", skill.package
    assert_includes skill.content, "# Next.js"
    assert_equal 24_531, skill.install_count
  end

  test "defaults scope to the session's project when scope_id is omitted" do
    stub_detail_endpoint

    result = InternalTools::MetaInstallSkill.new(
      params: { skill_id: @skill_id, scope_type: "Project" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]

    data = JSON.parse(result[:stdout])
    skill = Skill.find(data["id"])
    assert_equal "Project", skill.scope_type
    assert_equal @project.id, skill.scope_id
  end

  test "updates an existing skill in scope rather than creating a duplicate" do
    existing = create(
      :skill,
      scope: @project,
      name: "next-js-development",
      package: "vercel-labs/agent-skills@next-js-development",
      source: "vercel-labs/agent-skills",
      title: "Old Title",
      content: "old content"
    )
    stub_detail_endpoint

    assert_no_difference -> { Skill.count } do
      result = InternalTools::MetaInstallSkill.new(
        params: { skill_id: @skill_id, scope_type: "Project", scope_id: @project.id },
        session: @session
      ).execute

      assert_equal 0, result[:exit_code]
      data = JSON.parse(result[:stdout])
      assert_equal existing.id, data["id"]
    end

    assert_equal "Next.js Development", existing.reload.title
  end
end
