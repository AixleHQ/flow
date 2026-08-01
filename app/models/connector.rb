# frozen_string_literal: true

# Connector — one entry in the mirrored MCP connector catalog.
#
# A cache of someone else's data, not a domain record: the Official MCP Registry
# owns the truth and this table is rebuildable from a full re-sync. Installs do
# NOT reference it by foreign key (see MCPServer#connector_name), so a row may be
# rewritten or removed without touching working project configuration.
#
# scope: global (the catalog is the same for everyone; curation, if it ever
# arrives, belongs here rather than per-company).
class Connector < ApplicationRecord
  extend Enumerize

  # Registry moderation lifecycle. "deleted" is the registry's signal that an
  # entry "might be spam, malware, or illegal".
  enumerize :status, in: %i[active deprecated deleted], default: :active, predicates: true, scope: true

  validates :name, presence: true, uniqueness: true
  validates :status, presence: true

  # Discovery hides entries the registry pulled, per its guidance that
  # aggregators drop them from their index. Installs that already exist are NOT
  # removed — they stay running with a warning (decision, 2026-08-01) — which is
  # why deleted rows are retained here rather than destroyed.
  scope :discoverable, -> { where(status: %w[active deprecated]).where(is_latest: true) }

  # The catalog's default view.
  #
  # "Popular" is this platform's own install count, because the Official MCP
  # Registry publishes NO popularity signal at all — no installs, downloads or
  # ratings. Anything else on offer would be invented.
  #
  # The count orders but is never shown: an exact figure aggregated across every
  # company is tenant usage data, and a catalog has no business publishing it.
  # `featured` breaks the tie while the platform is young and every count is 0,
  # and recency breaks it after that.
  # Publisher tier, from the namespace the registry itself verified:
  #   0 — a reverse-DNS domain (com.notion, app.linear): proven by DNS or HTTP
  #       challenge, so it is the vendor's own server
  #   1 — io.github.*: proven by GitHub OAuth, so a real account, but anyone's
  # This is why the catalog does not look like four competing "Linear" entries:
  # the registry genuinely carries several, and the vendor's own leads.
  VENDOR_TIER = "CASE WHEN name LIKE 'io.github.%' THEN 1 ELSE 0 END"

  # Ordering, most decisive first:
  #   installs      — demand on THIS platform; the only first-party measurement
  #   featured      — a curated seed, so a brand-new catalog still opens on something
  #   bulk_publisher— namespaces publishing at scale sink below single-product ones
  #   vendor tier   — the vendor's own server beats a third party's wrapper
  #   recency       — last resort; on its own it surfaces only the newest noise
  scope :popular, lambda {
    order(Arel.sql(
            "install_count DESC, featured DESC, bulk_publisher ASC, " \
            "#{VENDOR_TIER} ASC, registry_updated_at DESC NULLS LAST"
          ))
  }

  # A namespace with this many connectors is publishing at scale rather than
  # shipping one product. Chosen from the real distribution: genuine vendors sit
  # in the single digits, while the largest namespaces carry 100–300 entries.
  BULK_PUBLISHER_THRESHOLD = 20

  # Curated seed for a cold catalog: widely-used connectors that should lead the
  # default view before real install counts exist. Names are registry names.
  # This is a display hint, NOT an allowlist — every connector in the mirror is
  # installable, featured or not.
  # Two complementary signals, because neither covers the catalog alone.
  #
  # The first group is VENDOR-VERIFIED: each namespace is a registrable domain
  # (exactly TLD + domain), which the registry grants only after a DNS or HTTP
  # ownership challenge — so a customer subdomain like `app.netlify.someones-app`
  # cannot pose as the vendor. These are hosted services with no public repo to
  # measure, so ownership is the only evidence available.
  #
  # The second group is MEASURED: GitHub stars on a repository the publisher
  # provably owns, from a one-off pass over 9,377 repositories (8,000 answered;
  # 1,206 registry entries point at repositories that no longer exist). These are
  # the top entries by star count, deduplicated by repository — a monorepo
  # shipping four MCP servers would otherwise take four slots on one project's
  # popularity. The cut-off sits around 3,300 stars.
  #
  # CAVEAT worth keeping in mind: stars belong to a REPOSITORY. For a server that
  # lives inside a large product repo, the count measures the product, not the
  # connector. It is evidence, not a verdict.
  #
  # This whole list is a seed for a catalog with no install history. `install_count`
  # is the real signal and outranks it the moment this platform has one.
  FEATURED = %w[
    app.linear/linear
    com.notion/mcp
    com.figma.mcp/mcp
    com.atlassian/atlassian-mcp-server
    com.supabase/mcp
    com.vercel/vercel-mcp
    com.stripe/mcp
    com.zapier/mcp
    com.airtable/mcp
    com.monday/monday.com
    com.paypal.mcp/mcp
    com.auth0/mcp
    com.webflow/mcp
    com.railway/mcp
    co.huggingface/hf-mcp-server
    io.snyk/mcp

    com.browser-use/browser-use
    io.github.netdata/mcp-server
    io.github.D4Vinci/Scrapling
    io.github.upstash/context7
    io.github.tldraw/tldraw
    io.github.metabase/mcp
    io.github.ChromeDevTools/chrome-devtools-mcp
    io.github.amruthpillai/reactive-resume
    io.github.bytedance/mcp-server-browser
    io.github.PostHog/mcp
    io.github.DeusData/codebase-memory-mcp
    io.github.microsoft/playwright-mcp
    io.github.github/github-mcp-server
    io.github.oraios/serena
    io.github.Skyvern-AI/skyvern
    io.github.screenpipe/screenpipe-mcp
    io.github.modelscope/funasr-mcp
    io.github.keploy/mcp
    io.github.googleapis/mcp-toolbox
    io.github.GLips/Figma-Context-MCP
    io.github.open-metadata/openmetadata-mcp
    io.github.coder/coder
    io.github.t8y2/dbx
    io.github.kubeshark/mcp
    io.github.wonderwhy-er/desktop-commander
    io.github.droidrun/mobilerun
    io.github.MervinPraison/praisonai
    io.github.firecrawl/firecrawl-mcp-server
    io.github.CursorTouch/Windows-MCP
    io.github.airweave-ai/search
    io.github.mobile-next/mobile-mcp
    io.github.JerBouma/financetoolkit
    com.mock-server/mockserver
    io.github.54yyyu/zotero-mcp
    io.github.firebase/firebase-mcp
    io.github.antvis/mcp-server-chart
    io.github.homeassistant-ai/ha-mcp
    io.github.txn2/kubefwd
    io.github.tolgee/tolgee
    io.github.KnockOutEZ/wigolo
    com.cloudflare.mcp/mcp
    io.github.IvanMurzak/Unity-MCP
    io.github.basicmachines-co/basic-memory
    com.microsoft/azure
    io.github.revolist/revogrid-mcp
    io.github.browserbase/mcp-server-browserbase
    io.github.grafana/mcp-grafana
    io.github.Ataraxy-Labs/sem
  ].freeze

  # Ranked full-text search over the generated tsvector. `websearch_to_tsquery`
  # accepts what users actually type (quoted phrases, OR, -exclusions) without
  # raising on syntax the way `to_tsquery` does.
  scope :search, ->(query) {
    query = query.to_s.strip
    next none if query.blank?

    sanitized = sanitize_sql_array([ "websearch_to_tsquery('simple', ?)", query ])
    where("search_vector @@ #{sanitized}")
      .order(Arel.sql("ts_rank(search_vector, #{sanitized}) DESC"), name: :asc)
  }

  def picker_name
    title.presence || name
  end

  # Whether the registry verified this publisher as the owner of a domain, rather
  # than as the holder of a GitHub account.
  def vendor_published?
    !name.to_s.start_with?("io.github.")
  end

  # An icon derived from the name, never curated by hand.
  #
  # The registry namespace already encodes who published a connector, so the
  # icon can be computed from it: a GitHub namespace has an avatar endpoint, and
  # a reverse-DNS namespace reverses back into the vendor's own domain, which
  # serves its own favicon. Nothing here is a lookup table that rots.
  #
  # PRIVACY: these load from the publisher's host, so a viewer's browser reveals
  # that it rendered this catalog entry. The UI falls back to a locally drawn
  # monogram when the fetch fails, so no icon is ever required.
  def icon_url
    namespace = name.to_s.split("/").first.to_s
    return nil if namespace.blank?

    if namespace.start_with?("io.github.")
      owner = namespace.delete_prefix("io.github.")
      return owner.present? ? "https://github.com/#{owner}.png?size=80" : nil
    end

    segments = namespace.split(".")
    return nil if segments.size < 2

    "https://#{segments.reverse.join('.')}/favicon.ico"
  end

  # Targets we can actually install, best first. A connector whose every target
  # is unsupported is still listed — the UI explains why rather than pretending
  # the entry does not exist.
  def installable_targets
    Array(manifest["targets"]).select { |t| t["supported"] }
  end

  def installable?
    installable_targets.any?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name title status version registry_updated_at created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
