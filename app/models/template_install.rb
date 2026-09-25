# frozen_string_literal: true

# One install of a catalog template into a project: which reviewed package
# (slug, version, commit, digest) went where, and who installed it. A project
# can hold several installs. There is no upgrade link — the installed resources
# are ordinary project resources from then on (design D4).
class TemplateInstall < ApplicationRecord
  belongs_to :project
  belongs_to :installed_by, class_name: "User", optional: true
  has_many :setup_items, -> { order(:position, :id) }, class_name: "TemplateSetupItem", dependent: :delete_all,
                                                        inverse_of: :template_install

  validates :namespace, :slug, :commit_sha, :package_digest, :idempotency_key, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :idempotency_key, uniqueness: { scope: :installed_by_id }

  def catalog_template = CatalogTemplate.find_by(namespace: namespace, slug: slug)

  def identifier = "#{namespace}/#{slug}"
end
