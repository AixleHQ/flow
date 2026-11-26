# frozen_string_literal: true

# Which product tour a member has finished (or skipped) in this company
# (docs/design/product-tour.md). Tour A is the full tour, tour B the viewer's.
class AddProductTourFinishedToCompanyMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :company_memberships, :product_tour_a_finished_at, :datetime
    add_column :company_memberships, :product_tour_b_finished_at, :datetime
  end
end
