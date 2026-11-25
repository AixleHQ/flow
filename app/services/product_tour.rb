# frozen_string_literal: true

# The Getting started page and the product tour (docs/design/product-tour.md).
# Tour A installs the Hello Flow starter template from the catalog, so it is
# offered only where the catalog carries it: a self-hosted install without
# access to the template repository has an empty catalog.
module ProductTour
  HELLO_FLOW = { namespace: "aixle", slug: "hello-flow" }.freeze

  # Cached because the user menu, on every page, reads it.
  def self.hello_flow_available?
    Rails.cache.fetch("product_tour/hello_flow_available", expires_in: 10.minutes) do
      CatalogTemplate.listed.exists?(**HELLO_FLOW)
    end
  end
end
