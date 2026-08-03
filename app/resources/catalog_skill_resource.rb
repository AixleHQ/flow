# frozen_string_literal: true

# One skills catalog entry as the browser sees it.
#
# `installs` is upstream's own figure and IS shown, unlike the connector catalog's
# install count: that one aggregates tenant behaviour across companies, while this
# one is already public on skills.sh. It is presented as what it is — opt-out CLI
# telemetry, inflated for multi-skill repos — not as a quality score.
class CatalogSkillResource < ApplicationResource
  # No `id`. A catalog entry is identified by its registry id: a live upstream hit
  # rendered on a typed query has no mirror row behind it (a GET must not write to a
  # table shared by every tenant), so a database id would be null exactly when the
  # entry is newest.
  attributes :registry_id, :source, :slug, :title, :description,
             :installs, :featured, :created_at, :updated_at

  typelize :string
  attribute :picker_name do |catalog_skill|
    catalog_skill.picker_name
  end

  # "source@slug" — the identifier an installed Skill carries, so the UI can tell
  # which catalog entries a project already has.
  typelize :string
  attribute :package do |catalog_skill|
    catalog_skill.package
  end

  # Derived from the GitHub owner in the registry id, never curated. Null when the
  # id yields nothing usable; the UI then draws a monogram.
  typelize :string?
  attribute :icon_url do |catalog_skill|
    catalog_skill.icon_url
  end

  typelize :string
  attribute :registry_url do |catalog_skill|
    catalog_skill.registry_url
  end

  # The worst verdict any audit provider reported. NULL means nobody audited this
  # skill — which the UI must not render as a clean bill of health.
  typelize :string?
  attribute :audit_risk do |catalog_skill|
    catalog_skill.audit_risk
  end

  # Every provider's verdict, worst first. Sent in full because providers disagree —
  # snyk has rated skills "high" that the others call "safe" — and collapsing that
  # into one badge would hide the most informative part of the signal.
  typelize audit_providers: "Array<{ provider: string; risk: string | null; score: number | null; " \
                            "alerts: number | null; analyzed_at: string | null }>"
  attribute :audit_providers do |catalog_skill|
    catalog_skill.audit_providers
  end
end
