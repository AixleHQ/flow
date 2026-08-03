# frozen_string_literal: true

# What people actually look for in the skills catalog, so the sweep can follow demand
# instead of only the seed list someone typed once.
#
# The static seeds in Skills::CatalogSync cover topics we guessed at; this table
# covers the ones we did not. A daily sweep over the most-searched terms mirrors what
# users are about to install, which is exactly the part of a 600k-skill registry worth
# having locally.
#
# DELIBERATELY NOT ATTRIBUTED. There is no user_id, project_id or company_id here, and
# there must not be: the table is global, so linking a term to a tenant would turn a
# ranking input into a cross-tenant log of what each customer is looking for. Terms
# are normalised, length-capped and shape-restricted before they land, and pruned to
# the top few hundred — enough to steer a sweep, not enough to profile anyone.
class CreateCatalogSearchQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_search_queries do |t|
      t.string :term, null: false
      t.integer :search_count, default: 0, null: false
      t.datetime :last_searched_at

      t.timestamps
    end

    add_index :catalog_search_queries, :term, unique: true
    # The daily sweep reads the top N by demand; pruning reads the stale tail.
    add_index :catalog_search_queries, %i[search_count last_searched_at],
              name: "index_catalog_search_queries_on_demand"
  end
end
