# frozen_string_literal: true

require "test_helper"

# Authorization matrix for the company-level ConfigItems controller (admin-only),
# via the shared AuthorizationMatrix harness. Every action gates purely on
# current_user.admin? (BaseContext, no project). Record scoping happens in the
# controller (ConfigItem.for_company(current_company)), so a foreign-company
# admin *passes* the admin-only policy but is scoped out of THIS company's rows
# (404) on record actions — while `create` lands in their own company (allowed).
class Web::Company::ConfigItemsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_company_authz_personas
    @item = create(:config_item, scope: @company)
  end

  teardown { teardown_authz }

  test "index: admin only (foreign admin sees their own empty list)" do
    assert_company_admin_only(kind: :read) { get company_config_items_path }
  end

  test "update: admin only; foreign admin scoped out of this company's record" do
    assert_company_admin_only(kind: :write) do
      patch company_config_item_path(@item), params: { config_item: { value: "updated" } }
    end
  end

  test "destroy: admin only; foreign admin scoped out of this company's record" do
    assert_company_admin_only(kind: :write) do
      delete company_config_item_path(@item)
    end
  end

  # `create` has no existing record to scope, so a foreign admin is not scoped
  # out — the admin-only policy passes and the item lands in their own company.
  test "create: admin only; foreign admin creates within their own company" do
    assert_role_matrix(
      { admin: :allowed_write, foreign_admin: :allowed_write,
        owner: :denied, collaborator: :denied, viewer: :denied, stranger: :denied },
      transport: :web
    ) do
      post company_config_items_path,
           params: { config_item: { name: "VAR_#{SecureRandom.hex(3)}", value: "v", item_type: "variable" } }
    end
  end
end
