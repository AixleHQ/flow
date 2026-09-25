# frozen_string_literal: true

require "test_helper"

# The real project_id/company_id columns beside the polymorphic scope pair, and
# what the database now refuses on its own (AddTenantColumnsToScopedResources).
class TenantColumnsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "a project-scoped row records its project and the project's company" do
    tool = create(:tool, scope: @project)

    assert_equal [ @project.id, @company.id ], [ tool.project_id, tool.company_id ]
  end

  test "a company-scoped asset records the company and no project" do
    asset = create(:asset, scope: @company, created_by: @user)

    assert_equal [ nil, @company.id ], [ asset.project_id, asset.company_id ]
  end

  test "a platform row belongs to no tenant" do
    tool = create(:tool, :internal)

    assert_equal [ nil, nil ], [ tool.project_id, tool.company_id ]
  end

  test "the database refuses tenant columns that disagree with the scope" do
    skill = create(:skill, scope: @project)
    other = create(:project, company: @company, owner: @user)

    assert_raises(ActiveRecord::StatementInvalid) { skill.update_columns(project_id: other.id) }
  end

  test "the database refuses a project paired with another company" do
    skill = create(:skill, scope: @project)

    assert_raises(ActiveRecord::StatementInvalid) { skill.update_columns(company_id: create(:company).id) }
  end

  test "the database refuses a repository whose integration belongs to another company" do
    repository = create(:repository, scope: @project)
    foreign = create(:integration, company: create(:company))

    assert_raises(ActiveRecord::InvalidForeignKey) { repository.update_columns(integration_id: foreign.id) }
  end
end
