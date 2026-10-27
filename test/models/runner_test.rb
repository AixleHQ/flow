# frozen_string_literal: true

require "test_helper"

class RunnerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "each type builds a valid runner" do
    %i[manual coder kubernetes].each do |type|
      runner = build(:runner, type, company: @company, created_by: @user)
      assert runner.valid?, "#{type}: #{runner.errors.full_messages.to_sentence}"
    end
  end

  # == validations ==

  test "requires a name, a type, a creator and a positive max_concurrency" do
    runner = Runner.new(company: @company, max_concurrency: 0)

    assert_not runner.valid?
    assert runner.errors.added?(:name, :blank)
    assert runner.errors.added?(:runner_type, :blank)
    assert runner.errors.added?(:created_by, :blank)
    assert runner.errors.of_kind?(:max_concurrency, :greater_than)
  end

  test "a name is unique per scope, ignoring case and deleted runners" do
    create(:runner, company: @company, created_by: @user, name: "Build box")

    assert_not build(:runner, company: @company, created_by: @user, name: "build BOX").valid?
    assert build(:runner, company: @company, created_by: @user, project: @project, name: "Build box").valid?
    assert build(:runner, company: create(:company), name: "Build box").valid?

    create(:runner, company: @company, created_by: @user, project: @project, name: "Project box").soft_delete!
    assert build(:runner, company: @company, created_by: @user, project: @project, name: "project box").valid?
  end

  test "a runner keeps its own name on update" do
    runner = create(:runner, company: @company, created_by: @user)

    assert runner.update(max_concurrency: 2)
  end

  test "max_environments is positive, and absent on a manual runner" do
    assert_not build(:runner, :coder, company: @company, created_by: @user, max_environments: 0).valid?
    assert build(:runner, :coder, company: @company, created_by: @user, max_environments: 3).valid?

    manual = build(:runner, :manual, company: @company, created_by: @user, max_environments: 3)
    assert_not manual.valid?
    assert manual.errors.added?(:max_environments, :present)
  end

  test "an integration is required on a coder runner and refused on the others" do
    coder = build(:runner, :coder, company: @company, created_by: @user, integration: nil)
    assert_not coder.valid?
    assert coder.errors.added?(:integration, :blank)

    integration = create(:integration, :coder, company: @company)
    manual = build(:runner, :manual, company: @company, created_by: @user, integration: integration)
    assert_not manual.valid?
    assert manual.errors.added?(:integration, :present)
  end

  test "the project must belong to the runner's company" do
    foreign_project = create(:project, :standalone)
    runner = build(:runner, company: @company, created_by: @user, project: foreign_project)

    assert_not runner.valid?
    assert_includes runner.errors[:project], "must belong to the same company"
  end

  # == §2.6: which Coder integration a runner may use ==

  test "a coder runner refuses an integration of another provider" do
    runner = build(:runner, :coder, company: @company, created_by: @user,
                                    integration: create(:integration, :gitlab, company: @company))

    assert_not runner.valid?
    assert_includes runner.errors[:integration], "must be a Coder integration"
  end

  test "a coder runner refuses another company's integration" do
    runner = build(:runner, :coder, company: @company, created_by: @user,
                                    integration: create(:integration, :coder, company: create(:company)))

    assert_not runner.valid?
    assert_includes runner.errors[:integration], "must belong to the same company"
  end

  test "a company runner may use only a company-wide integration" do
    project_integration = create(:integration, :coder, company: @company, project: @project)
    runner = build(:runner, :coder, company: @company, created_by: @user, integration: project_integration)

    assert_not runner.valid?
    assert_includes runner.errors[:integration], "must be company-wide"
  end

  test "a project runner may use a company-wide integration or its own project's, not another project's" do
    company_wide = create(:integration, :coder, company: @company)
    own = create(:integration, :coder, company: @company, project: @project)
    other = create(:integration, :coder, company: @company,
                                         project: create(:project, company: @company, owner: @user))

    assert build(:runner, :coder, company: @company, created_by: @user, project: @project, integration: company_wide).valid?
    assert build(:runner, :coder, company: @company, created_by: @user, project: @project, integration: own).valid?

    runner = build(:runner, :coder, company: @company, created_by: @user, project: @project, integration: other)
    assert_not runner.valid?
    assert_includes runner.errors[:integration], "must be company-wide or this project's"
  end

  # == reuse_policy ==

  test "reuse_policy defaults to reuse on manual and coder, fresh on kubernetes" do
    defaults = %i[manual coder kubernetes].to_h do |type|
      [ type, create(:runner, type, company: @company, created_by: @user).reuse_policy ]
    end

    assert_equal({ manual: "reuse", coder: "reuse", kubernetes: "fresh" }, defaults)
  end

  test "a given reuse_policy is kept, except reuse on kubernetes, which is refused" do
    assert_equal "fresh", create(:runner, :manual, company: @company, created_by: @user, reuse_policy: :fresh).reuse_policy

    kubernetes = build(:runner, :kubernetes, company: @company, created_by: @user, reuse_policy: :reuse)
    assert_not kubernetes.valid?
    assert_includes kubernetes.errors[:reuse_policy], "must be fresh on a kubernetes runner"
  end

  # == visible_for_project ==

  test "visible_for_project returns the project's runners and the company's, never deleted or foreign ones" do
    own = create(:runner, company: @company, created_by: @user, project: @project)
    company_runner = create(:runner, company: @company, created_by: @user)
    create(:runner, company: @company, created_by: @user, project: create(:project, company: @company, owner: @user))
    create(:runner, company: create(:company))
    create(:runner, :project_runner, company: create(:company))
    create(:runner, company: @company, created_by: @user).soft_delete!
    create(:runner, company: @company, created_by: @user, project: @project).soft_delete!

    assert_equal [ own.id, company_runner.id ].sort, Runner.visible_for_project(@project).pluck(:id).sort
  end

  # == what the database refuses on its own ==

  test "the database refuses rows that skip validations" do
    runner = create(:runner, :manual, company: @company, created_by: @user, project: @project)
    coder = create(:runner, :coder, company: @company, created_by: @user)
    foreign_company = create(:company)
    foreign_integration = create(:integration, :coder, company: foreign_company)
    twin = create(:runner, company: @company, created_by: @user, project: @project)

    [
      [ "runners_max_concurrency_positive", runner, { max_concurrency: 0 } ],
      [ "runners_coder_integration", coder, { integration_id: nil } ],
      [ "runners_coder_integration", runner, { integration_id: coder.integration_id } ],
      [ "runners_manual_no_pool_size", runner, { max_environments: 2 } ],
      [ "runners_max_environments_positive", coder, { max_environments: 0 } ],
      [ "fk_runners_project_company", runner, { company_id: foreign_company.id } ],
      [ "fk_runners_integration_company", coder, { integration_id: foreign_integration.id } ],
      [ "index_runners_on_scope_and_name", twin, { name: runner.name.upcase } ]
    ].each do |constraint, row, values|
      error = assert_raises(ActiveRecord::StatementInvalid, constraint) do
        Runner.transaction(requires_new: true) { Runner.where(id: row.id).update_all(values) }
      end
      assert_includes error.message, constraint
    end
  end

  test "an integration a runner uses, deleted or not, is not destroyed" do
    runner = create(:runner, :coder, company: @company, created_by: @user)
    runner.soft_delete!
    integration = runner.integration

    assert_not integration.destroy
    assert integration.errors.of_kind?(:base, :"restrict_dependent_destroy.has_many")
    assert Integration.exists?(integration.id)
  end

  test "the database accepts a runner with a deleted runner's name" do
    deleted = create(:runner, company: @company, created_by: @user)
    deleted.soft_delete!
    runner = create(:runner, company: @company, created_by: @user)

    assert_nothing_raised { Runner.where(id: runner.id).update_all(name: deleted.name) }
  end
end
