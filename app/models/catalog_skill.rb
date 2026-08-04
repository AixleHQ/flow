# frozen_string_literal: true

# CatalogSkill — one entry in the mirrored skills.sh catalog.
#
# A cache of someone else's data, not a domain record: skills.sh owns the truth and
# this table is rebuildable by another sweep (Skills::CatalogSync). Installs do NOT
# reference it — an installed Skill carries its own content — so a row can be
# rewritten or removed without touching project configuration.
#
# scope: global (the catalog is the same for everyone).
class CatalogSkill < ApplicationRecord
  validates :registry_id, presence: true, uniqueness: true
  validates :source, presence: true
  validates :slug, presence: true

  # A source publishing this many skills is shipping a collection rather than a
  # product. Chosen from the real distribution: `larksuite/cli` carries ~25
  # near-identical entries and `github/awesome-copilot` hundreds, while a
  # single-purpose skill repo sits in the low single digits. Anthropic's official
  # repo (17 skills) stays under the line, and it is `featured` regardless.
  BULK_PUBLISHER_THRESHOLD = 20

  # Ordering, most decisive first. This is NOT `installs DESC` first, and the
  # difference is measured rather than aesthetic: over 3,702 sampled skills,
  # `larksuite/cli` sums to 9.9M installs across ~25 skills whose per-skill figures
  # are implausibly flat (393k–399k), and fifteen of the top twenty-five by raw
  # installs are `lark-*`. Leading with installs would hand the entire default view
  # to one publisher.
  #
  #   featured       — a curated seed leads, so a cold catalog opens on something real
  #   bulk_publisher — collections sink below single-product repos
  #   installs       — upstream telemetry: real demand, but gameable and repo-inflated
  #   install_count  — demand on THIS platform; first-party, so it breaks ties honestly
  #   registry_synced_at — last resort
  RANKING = "featured DESC, bulk_publisher ASC, installs DESC, " \
            "install_count DESC, registry_synced_at DESC NULLS LAST"

  scope :popular, -> { order(Arel.sql(RANKING)) }

  # The description-backfill queue: rows still missing a description,
  # least-recently-attempted first.
  #
  # `description_checked_at` leads, and that is the whole point. A SKILL.md
  # legitimately without a `description` key yields nil, so `description IS NULL`
  # cannot tell "never looked" from "looked, nothing there" — and a queue led by
  # RANKING re-offers the same unanswerable rows first on every run until they have
  # eaten the entire per-run budget. This ordering gives every row a turn before any
  # row gets a second one.
  #
  # RANKING breaks ties, which on a cold catalog is every row — so a first pass still
  # describes what the grid actually renders before it works through the tail.
  scope :undescribed_first, lambda {
    where(description: nil)
      .order(Arel.sql("description_checked_at ASC NULLS FIRST, #{RANKING}"))
  }

  # One entry per publisher, best first. Ranking alone is not enough: a repo with
  # twenty-five similar skills would otherwise fill the grid even after the
  # bulk-publisher penalty, because the penalty orders publishers — it does not
  # thin them out.
  scope :one_per_source, lambda {
    from(
      all.select("DISTINCT ON (catalog_skills.source) catalog_skills.*")
         .order(Arel.sql("catalog_skills.source, #{RANKING}")),
      :catalog_skills
    )
  }

  # Ranked full-text search over the generated tsvector. `websearch_to_tsquery`
  # accepts what people actually type (quoted phrases, OR, -exclusions) instead of
  # raising on syntax `to_tsquery` rejects.
  scope :search, ->(query) {
    query = query.to_s.strip
    next none if query.blank?

    sanitized = sanitize_sql_array([ "websearch_to_tsquery('simple', ?)", query ])
    where("search_vector @@ #{sanitized}")
      .order(Arel.sql("ts_rank(search_vector, #{sanitized}) DESC"), slug: :asc)
  }

  # Curated seed for a cold catalog. Registry ids, deduplicated by source so the
  # default view opens on twenty different publishers rather than one publisher's
  # twenty skills.
  #
  # Two signals, because neither covers the list alone:
  #
  #   OFFICIAL — `anthropics/skills` is the Agent Skills reference repository, and
  #   the format's own maintainer. Its skills are the closest thing to a
  #   vendor-verified entry that this registry offers, since a skills.sh id is a
  #   GitHub coordinate with no ownership proof attached (unlike the MCP registry's
  #   DNS-challenged namespaces).
  #
  #   MEASURED — top entries by upstream `installs` from a 20-query sweep of the
  #   public search endpoint (3,702 unique skills, 2026-08-03), after dropping
  #   repo-level-inflated collections.
  #
  # CAVEAT worth keeping: `installs` is opt-out CLI telemetry and the only ranking
  # signal skills.sh publishes. It is evidence, not a verdict. This list is a seed
  # for a catalog with no history of its own; `install_count` is the first-party
  # signal and grows into the tiebreaker.
  FEATURED = %w[
    anthropics/skills/frontend-design
    anthropics/skills/mcp-builder
    anthropics/skills/skill-creator
    anthropics/skills/webapp-testing
    anthropics/skills/canvas-design
    anthropics/skills/brand-guidelines
    anthropics/skills/theme-factory
    anthropics/skills/web-artifacts-builder
    anthropics/skills/doc-coauthoring
    anthropics/skills/algorithmic-art
    anthropics/skills/pdf
    anthropics/skills/docx
    anthropics/skills/xlsx
    anthropics/skills/pptx
    anthropics/skills/claude-api

    vercel-labs/agent-skills/vercel-react-best-practices
    vercel-labs/agent-skills/web-design-guidelines
    vercel-labs/agent-browser/agent-browser
    vercel-labs/skills/find-skills
    mattpocock/skills/grill-with-docs
    microsoft/azure-skills/azure-deploy
    microsoft/playwright-cli/playwright-cli
    supabase/agent-skills/supabase-postgres-best-practices
    firebase/agent-skills/developing-genkit-python
    shadcn/ui/shadcn
    obra/superpowers/test-driven-development
    obra/superpowers/requesting-code-review
    currents-dev/playwright-best-practices-skill/playwright-best-practices
    emilkowalski/skills/emil-design-eng
    ast-grep/agent-skill/ast-grep
    trailofbits/skills/audit-prep-assistant
    leonxlnx/taste-skill/design-taste-frontend
    nextlevelbuilder/ui-ux-pro-max-skill/ui-ux-pro-max
  ].freeze

  # Risk levels the audit providers use, least to most severe. "unknown" is a
  # provider saying it could not tell — distinct from no audit at all, and distinct
  # again from a label we have never seen.
  RISK_SEVERITY = { "safe" => 0, "low" => 1, "medium" => 2, "high" => 3, "critical" => 4 }.freeze
  INCONCLUSIVE = "unknown"
  # An unrecognised label is sorted as if it were the worst thing we know about.
  # A provider inventing "moderate" or "warn" must not silently become "nobody
  # audited this" — under-reporting a flag is the more dangerous failure.
  UNRECOGNISED_SEVERITY = RISK_SEVERITY.fetch("critical")
  # Above this, the UI interrupts the install rather than merely labelling it.
  WARN_RISK = %w[high critical].freeze

  # Severity used for ordering. Returns nil for "no verdict at all".
  def self.risk_severity(risk)
    risk = risk.to_s
    return nil if risk.blank?
    return -1 if risk == INCONCLUSIVE

    RISK_SEVERITY.fetch(risk, UNRECOGNISED_SEVERITY)
  end

  # The worst verdict any provider reported, or nil when nobody audited it. Derived
  # here rather than trusted from upstream so `audit_risk` and `audit` cannot drift.
  #
  # The payload is third-party JSON, so nothing about its shape is assumed: a
  # provider value that is not an object, or a risk that is not a string, is skipped
  # rather than allowed to raise inside a sweep or a page render.
  def self.worst_risk(audit)
    verdicts = provider_entries(audit).filter_map { |_name, data| data["risk"].presence }
    return nil if verdicts.empty?

    conclusive = verdicts.reject { |risk| risk == INCONCLUSIVE }
    # Every provider shrugged: that is a real state ("we looked, we can't say"), and
    # it must not render the same as never having been audited.
    return INCONCLUSIVE if conclusive.empty?

    conclusive.max_by { |risk| risk_severity(risk) }
  end

  # Provider name → payload pairs, keeping only well-formed entries.
  def self.provider_entries(audit)
    return [] unless audit.is_a?(Hash)

    audit.filter_map { |name, data| [ name, data ] if data.is_a?(Hash) }
  end

  # NOT "is this safe". Nobody looking is not the same as nothing found.
  def audited?
    audit_risk.present?
  end

  # True for a flagged verdict AND for a label we do not recognise.
  def audit_warning?
    return false if audit_risk.blank? || audit_risk == INCONCLUSIVE

    WARN_RISK.include?(audit_risk) || !RISK_SEVERITY.key?(audit_risk)
  end

  # [{ provider:, risk:, score:, alerts:, analyzed_at: }], worst first, so the UI can
  # show that providers disagree instead of implying a single verdict.
  def audit_providers
    self.class.provider_entries(audit).map do |name, data|
      {
        provider: name,
        risk: data["risk"].presence,
        score: data["score"],
        alerts: data["alerts"],
        analyzed_at: data["analyzedAt"]
      }
    end.sort_by { |entry| -(self.class.risk_severity(entry[:risk]) || -2) }
  end

  def package
    "#{source}@#{slug}"
  end

  def picker_name
    title.presence || slug
  end

  def owner
    source.to_s.split("/").first
  end

  # Icons are computed, never curated: a skills.sh id is a GitHub coordinate, so
  # the owner's avatar endpoint is derivable and nothing here can rot into a stale
  # lookup table.
  #
  # PRIVACY: this loads from github.com, so a viewer's browser reveals that it
  # rendered this card. The UI falls back to a locally drawn monogram when the
  # fetch fails, so no icon is ever required.
  def icon_url
    owner.present? ? "https://github.com/#{owner}.png?size=80" : nil
  end

  def registry_url
    "https://skills.sh/#{registry_id}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[registry_id source slug title installs install_count featured bulk_publisher created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
