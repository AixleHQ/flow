# frozen_string_literal: true

# Third-party security audits for catalog entries.
#
# A skill is instructions injected into an agent's context, and this catalog offers
# no ownership proof: a skills.sh id is a GitHub coordinate, unlike the MCP
# registry's DNS-challenged namespaces. Audits are the only external judgement
# available, and they turn out to be reachable — the skills CLI queries
# add-skill.vercel.sh/audit unauthenticated before every install, while the
# documented `/api/v1/skills/audit/...` endpoint is OIDC-gated.
#
# The whole per-provider map is stored rather than one verdict, because providers
# disagree: snyk has rated skills "high" that ath, socket and zeroleaks call "safe".
# Flattening that to a single badge would hide the disagreement, which is itself the
# most useful part of the signal.
#
# `audit_risk` is the worst risk any provider reported, for ordering and filtering.
# NULL means nobody audited it — which is not the same as safe, and the UI must not
# render it as such.
class AddAuditsToCatalogSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_skills, :audit, :jsonb, default: {}, null: false
    add_column :catalog_skills, :audit_risk, :string
    add_column :catalog_skills, :audited_at, :datetime

    add_index :catalog_skills, :audit_risk
  end
end
