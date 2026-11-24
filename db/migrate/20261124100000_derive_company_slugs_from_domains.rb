# frozen_string_literal: true

# A company's slug becomes part of every URL it owns (/company/<slug>/…), and
# it is now the registrable label of its email domain rather than its name.
# Nothing linked to a slug before, so the existing ones are rewritten once,
# oldest company first, so that it keeps the bare label when two domains share
# one (acme.com and acme.io).
class DeriveCompanySlugsFromDomains < ActiveRecord::Migration[8.1]
  RESERVED = %w[
    analytics assets auth_policies billing_cancellation billing_checkout
    billing_invoice_payment domain_verification feedback folders identity_providers
    integrations marketplace_license_proposal members memberships projects
    scim_configuration sessions settings switch template_installs user workflow_catalog
  ].freeze

  def up
    taken = Set.new
    slugs = select_rows("SELECT id, email_domain, name FROM companies ORDER BY id").map do |id, domain, name|
      slug = unique_slug(base_for(domain).presence || name.to_s.parameterize.presence || "company", taken)
      taken << slug
      [ id, slug ]
    end

    # Every row moves off its old slug first: one company's new slug can be
    # another's old one, and the unique index holds at each statement.
    execute "UPDATE companies SET slug = 'migrating-' || id"
    slugs.each do |id, slug|
      execute "UPDATE companies SET slug = #{connection.quote(slug)} WHERE id = #{Integer(id)}"
    end
  end

  def down
    # The derived slugs are valid slugs; nothing links to the old ones.
  end

  private

  def base_for(domain)
    label = begin
      PublicSuffix.parse(domain.to_s).sld
    rescue PublicSuffix::Error
      domain.to_s.split(".").first
    end
    label.to_s.parameterize
  end

  def unique_slug(base, taken)
    slug = base
    counter = 1
    while RESERVED.include?(slug) || taken.include?(slug)
      slug = "#{base}-#{counter}"
      counter += 1
    end
    slug
  end
end
