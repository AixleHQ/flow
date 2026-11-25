# frozen_string_literal: true

# Members who finished onboarding before the product tour existed count as having
# finished it: without this, every existing member would be sent to Getting
# started the moment the product_tour flag is turned on.
class BackfillProductTourFinished < ActiveRecord::Migration[8.1]
  class MigrationMembership < ActiveRecord::Base
    self.table_name = "company_memberships"
  end

  def up
    MigrationMembership.where.not(onboarding_completed_at: nil).in_batches(of: 1000) do |batch|
      batch.update_all("product_tour_a_finished_at = COALESCE(product_tour_a_finished_at, onboarding_completed_at), " \
                       "product_tour_b_finished_at = COALESCE(product_tour_b_finished_at, onboarding_completed_at)")
    end
  end

  def down; end
end
