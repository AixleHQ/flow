# frozen_string_literal: true

require "test_helper"

class TenantIdsValidatorTest < ActiveSupport::TestCase
  class Holder
    include ActiveModel::Validations

    attr_accessor :project, :asset_ids, :kept_ids

    validates :asset_ids, tenant_ids: { model: Asset }
    validates :kept_ids, tenant_ids: { model: Asset, lenient: true }

    def initialize(project:, asset_ids: [], kept_ids: [])
      @project = project
      @asset_ids = asset_ids
      @kept_ids = kept_ids
    end
  end

  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.companies.first, owner: @user)
  end

  test "accepts the project's own rows and the company's" do
    own = create(:asset, scope: @project, created_by: @user)
    company_wide = create(:asset, scope: @project.company, created_by: @user)

    assert Holder.new(project: @project, asset_ids: [ own.id, company_wide.id ]).valid?
  end

  test "refuses another company's row without saying whether it exists" do
    foreign = create(:asset, scope: create(:project, :standalone), created_by: @user)
    holder = Holder.new(project: @project, asset_ids: [ foreign.id, 0 ])

    assert_not holder.valid?
    assert_equal [ "must belong to this project (not found: 0, #{foreign.id})" ], holder.errors[:asset_ids]
  end

  test "lenient lets a deleted row's id through, but never a foreign one" do
    foreign = create(:asset, scope: create(:project, :standalone), created_by: @user)

    assert Holder.new(project: @project, kept_ids: [ 0 ]).valid?
    assert_not Holder.new(project: @project, kept_ids: [ foreign.id ]).valid?
  end
end
