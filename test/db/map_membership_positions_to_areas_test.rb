# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261120100001_map_membership_positions_to_areas")

class MapMembershipPositionsToAreasTest < ActiveSupport::TestCase
  test "each stored role moves to the area that holds it" do
    company = create(:company)
    memberships = %w[dev pm_po_ba designer cto qa other].index_with do |role|
      create(:user, company: company).company_memberships.sole.tap { |m| m.update_columns(position: role) }
    end

    migration = MapMembershipPositionsToAreas.new
    migration.suppress_messages { migration.up }

    assert_equal({ "dev" => "engineering", "pm_po_ba" => "product", "designer" => "design", "cto" => "executive",
                   "qa" => "qa", "other" => "other" },
                 memberships.transform_values { |m| m.reload.read_attribute(:position) })
  end
end
