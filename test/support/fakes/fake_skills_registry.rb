# frozen_string_literal: true

# Canonical fake for Skills::RegistryClient. Never stub skills.sh HTTP outside the
# client's own contract test (docs/testing.md R3/R4) — inject this instead:
#
#   registry = FakeSkillsRegistry.new
#   registry.add("anthropics/skills/frontend-design", installs: 734_415)
#   registry.bundle("anthropics/skills", "frontend-design",
#                   skill_md: "---\nname: frontend-design\ndescription: d\n---\n\nbody")
#   Skills::CatalogSync.new(client: registry, delay: 0).call
#
# Kept interface-identical to the real client by
# test/services/skills/registry_client_test.rb, which pins the wire shapes.
class FakeSkillsRegistry
  Entry = Skills::RegistryClient::Entry
  Bundle = Skills::RegistryClient::Bundle

  # Every search/download call, so a test can assert the sweep actually paced
  # through its seeds rather than asserting on mirrored rows alone.
  attr_reader :searches, :downloads, :audit_requests
  attr_accessor :search_results

  def initialize
    @entries = []
    @bundles = {}
    @audits = {}
    @searches = []
    @downloads = []
    @audit_requests = []
    # When set, every search returns exactly this, ignoring the query.
    @search_results = nil
  end

  # Registers an entry discoverable by any query matching its id.
  def add(registry_id, installs: 0, name: nil)
    parts = registry_id.split("/")
    source = parts[0..-2].join("/")
    slug = parts.last
    @entries << Entry.new(id: registry_id, slug: slug, name: name || slug, source: source, installs: installs)
    self
  end

  def bundle(source, slug, skill_md:, content_hash: "sha256:fake")
    @bundles["#{source}/#{slug}"] = Bundle.new(
      files: [ { "path" => "SKILL.md", "contents" => skill_md } ],
      content_hash: content_hash
    )
    self
  end

  # Mirrors the real client's contract: a query under two characters never reaches
  # the endpoint, an `owner` filter narrows to that publisher, and failures surface
  # as an empty array rather than an exception.
  #
  # Every registered entry answers every query. Upstream search is fuzzy and
  # semantic, so pretending to reproduce its matching would only couple tests to
  # whichever seed word happened to appear in a fixture id — the sweep's job is to
  # mirror what comes back, not to predict what matches.
  def search(query, limit: 100, owner: nil)
    @searches << { query: query, limit: limit, owner: owner }
    return [] if query.to_s.strip.length < Skills::RegistryClient::MIN_QUERY_LENGTH
    return Array(@search_results).first(limit) if @search_results

    matches = @entries
    matches = matches.select { |entry| entry.source.to_s.start_with?("#{owner}/") } if owner.present?
    matches.first(limit)
  end

  # Set to make every download raise, mirroring the endpoint's 60-per-hour ceiling.
  attr_accessor :rate_limited

  def download(source, slug)
    @downloads << "#{source}/#{slug}"
    raise Skills::RegistryClient::RateLimited, "download rate limit exceeded" if @rate_limited

    @bundles["#{source}/#{slug}"]
  end

  # Registers one provider's verdict, mirroring the audit endpoint's per-provider
  # shape. Call it twice for the same skill to model providers disagreeing, which
  # they really do.
  def audit(source, slug, provider: "socket", risk: "safe", score: nil, alerts: nil,
            analyzed_at: "2026-03-18T16:47:53.806Z")
    entry = { "risk" => risk, "analyzedAt" => analyzed_at }
    entry["score"] = score if score
    entry["alerts"] = alerts if alerts

    @audits[source] ||= {}
    @audits[source][slug] ||= {}
    @audits[source][slug][provider] = entry
    self
  end

  def audits(source, slugs)
    @audit_requests << { source: source, slugs: Array(slugs) }
    (@audits[source] || {}).slice(*Array(slugs))
  end
end
