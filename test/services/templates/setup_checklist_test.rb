# frozen_string_literal: true

require "test_helper"

class Templates::SetupChecklistTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :employee, :onboarding_completed)
    @company = @user.companies.first
    create(:tool, :system, name: "board_add_comment")
    package = Templates::Package.from_directory(Rails.root.join("test/fixtures/files/templates/dev-team-sdlc"))
    template = CatalogTemplate.new.assign_package(package, commit_sha: "a" * 40).tap(&:save!)
    result = Templates::Installer.new(catalog_template: template, user: @user, target: { company: @company },
                                      idempotency_key: "k").apply
    @install = result.install
    @project = result.project
    @checklist = Templates::SetupChecklist.new(@install, user: @user)
  end

  def item(ref) = @install.setup_items.find_by!(ref: ref)
  def workflow = @project.workflows.sole

  test "adding a secret creates it and attaches it where the template referenced it" do
    @checklist.add_secret!(item("secret:SENTRY_TOKEN"), "tok-1")

    token = @project.config_items.find_by!(name: "SENTRY_TOKEN")
    assert_equal "tok-1", token.decrypted_value
    assert_includes workflow.reload.base_config_item_ids, token.id
    assert_equal "done", item("secret:SENTRY_TOKEN").status
  end

  test "a secret added on the project's config page is adopted on refresh" do
    token = @project.config_items.create!(name: "SENTRY_TOKEN", item_type: "secret", value: "tok-2")

    @checklist.refresh!

    assert_equal "done", item("secret:SENTRY_TOKEN").status
    assert_includes workflow.reload.base_config_item_ids, token.id
  end

  test "an integration connected elsewhere resolves its item on refresh" do
    create(:integration, company: @company, provider: :github, status: :active, connected_by: @user)

    @checklist.refresh!

    assert_equal "done", item("integration:github").status
  end

  test "attaching a repository adds it to the workflow that needs one" do
    repository = create(:repository, scope: @project, integration: create(:integration, company: @company))

    @checklist.attach_repository!(item("repository:app_repo"), repository.id)

    assert_equal [ repository.id ], workflow.reload.base_repository_ids
    assert_equal "done", item("repository:app_repo").status
  end

  test "activating a column trigger restores the template's own mode" do
    @checklist.activate_trigger!(item("trigger:0"))

    binding = ColumnWorkflowBinding.find(item("trigger:0").detail["trigger_id"])
    assert_equal "auto", binding.trigger_mode
    assert_equal "done", item("trigger:0").status
  end

  test "an unattended trigger on a workflow with manual steps is refused with the reason" do
    error = assert_raises(Templates::SetupChecklist::Error) { @checklist.activate_trigger!(item("trigger:1")) }

    assert_match(/enable auto-run on these steps first/, error.message)
    assert_equal false, TriggerBinding.find(item("trigger:1").detail["trigger_id"]).enabled # rubocop:disable Minitest/RefuteFalse
    assert_equal "pending", item("trigger:1").status
  end

  test "an item can be dismissed, and an item of another install cannot be acted on" do
    @checklist.dismiss!(item("integration:github"))
    assert_equal "dismissed", item("integration:github").status

    other = create(:project, company: @company, owner: @user).template_installs.create!(
      installed_by: @user, namespace: "acme", slug: "x", version: 1, commit_sha: "b" * 40, package_digest: "d", idempotency_key: "other"
    )
    foreign = other.setup_items.create!(kind: "secret", ref: "secret:X", detail: { "name" => "X" })
    assert_raises(Templates::SetupChecklist::Error) { @checklist.add_secret!(foreign, "v") }
  end
end
