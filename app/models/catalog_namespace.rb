# frozen_string_literal: true

# CatalogNamespace — one publisher from the templates repository's
# namespaces.yaml. A template belongs to a namespace, and only the namespace's
# owners (GitHub logins) may change its templates; the repository's CI enforces
# that. `verified` is set by the Flow maintainers and shown as a badge.
class CatalogNamespace < ApplicationRecord
  validates :name, presence: true, uniqueness: true, format: { with: Templates::Package::NAME_FORMAT }
  validates :display_name, :synced_at, presence: true

  def templates = CatalogTemplate.where(namespace: name)
end
