# frozen_string_literal: true

# Onboarding asks which area of the company a person works in instead of picking
# an SDLC role, so each stored role moves to the area that holds it. `qa` and
# `other` exist in both lists and stay as they are.
class MapMembershipPositionsToAreas < ActiveRecord::Migration[8.1]
  ROLE_AREAS = { "dev" => "engineering", "pm_po_ba" => "product", "designer" => "design", "cto" => "executive" }.freeze

  def up
    remap ROLE_AREAS
  end

  def down
    remap ROLE_AREAS.invert.merge("marketing" => "other", "operations" => "other", "finance" => "other")
  end

  private

  def remap(mapping)
    mapping.each do |from, to|
      execute "UPDATE company_memberships SET position = #{connection.quote(to)} " \
              "WHERE position = #{connection.quote(from)}"
    end
  end
end
