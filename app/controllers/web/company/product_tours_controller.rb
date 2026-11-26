# frozen_string_literal: true

# Records that the current member finished (or skipped) a product tour in this
# company. The tour's progress itself lives in the browser.
class Web::Company::ProductToursController < Web::Company::ApplicationController
  requires_feature :product_tour
  allow_viewer_writes

  def update
    variant = params.require(:variant).to_s
    return head :unprocessable_entity unless %w[a b].include?(variant)

    current_membership.finish_product_tour!(variant)
    head :no_content
  end
end
