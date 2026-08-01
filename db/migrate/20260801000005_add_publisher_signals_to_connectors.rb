# frozen_string_literal: true

# A quality signal the registry does not publish but its data reveals.
#
# The official registry is open, so it carries both a vendor's single official
# server and namespaces that have published hundreds of generated or re-listed
# ones. Namespace volume separates them without anyone curating a blocklist: a
# publisher with one carefully-made connector looks nothing like one with 300.
#
# `bulk_publisher` demotes the latter in the default view. It is a RANKING
# signal only — every connector stays searchable and installable, in keeping
# with the catalog's no-allowlist stance.
class AddPublisherSignalsToConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors, :bulk_publisher, :boolean, default: false, null: false
    add_index :connectors, :bulk_publisher
  end
end
