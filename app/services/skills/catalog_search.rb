# frozen_string_literal: true

module Skills
  # Browsing and searching the skills catalog, for every surface that offers it
  # (the skills page and the personal-MCP `search_skill_registry` tool).
  #
  # Blank (or too-short) query → the default browse view, served from the mirror.
  # A real query → upstream, because skills.sh's fuzzy search beats anything the
  # mirror can do and the mirror is incomplete by construction.
  #
  # NOTHING IS PERSISTED HERE. Both callers authorize as a project READ, so a
  # viewer who is denied `create?` must not be able to write rows into a table
  # shared by every tenant, or trigger an outbound request per keystroke, just by
  # loading a URL or calling a read-only tool. Upstream hits are returned as
  # UNSAVED records; the weekly sweep owns the mirror.
  class CatalogSearch
    # Comfortably above the curated seed so the default view is never a truncated
    # version of it.
    PAGE_SIZE = 60
    # Upstream is rate-limited per IP with no published number, and every debounced
    # keystroke from every member arrives here. Short-lived caching keeps a room full
    # of people typing from spending the whole deployment's budget on the same queries.
    CACHE_TTL = 5.minutes

    def self.call(...) = new(...).call

    def initialize(query, limit: PAGE_SIZE)
      @query = query.to_s.strip
      @limit = limit
    end

    # @return [Array<CatalogSkill>] mirrored rows, plus unsaved rows for upstream
    #   hits that are not mirrored yet
    def call
      return default_entries unless reaches_upstream?

      entries = cached_search
      # Upstream unreachable, or nothing matched: fall back to full-text over
      # whatever is mirrored rather than returning an empty catalog.
      return CatalogSkill.search(@query).limit(@limit).to_a if entries.empty?

      merge_with_mirror(entries)
    end

    # Whether this query is long enough for the upstream endpoint to accept it.
    def reaches_upstream?
      @query.length >= RegistryClient::MIN_QUERY_LENGTH
    end

    private

    def default_entries
      CatalogSkill.one_per_source.popular.limit(@limit).to_a
    end

    # Recording happens inside the cache-miss block on purpose: a debounced field
    # would otherwise write once per keystroke, and with the cache a term is
    # recorded at most once per window no matter how many people are typing it.
    # The term steers a later sweep and is stored unattributed — see CatalogSearchQuery.
    def cached_search
      Rails.cache.fetch([ "skills-catalog-search", @query ], expires_in: CACHE_TTL) do
        CatalogSearchQuery.record(@query)
        RegistryClient.search(@query, limit: @limit)
      end
    end

    # Upstream relevance order is preserved: the endpoint ranks by fuzzy match, and
    # re-sorting by popularity would push the exact-name hit below a tangential match
    # with more installs. Mirrored rows are reused where they exist so a result keeps
    # its description and audit verdicts; anything unmirrored renders from the search
    # payload alone.
    def merge_with_mirror(entries)
      mirrored = CatalogSkill.where(registry_id: entries.map(&:id).compact).index_by(&:registry_id)

      entries.map { |entry| mirrored[entry.id] || transient(entry) }
    end

    def transient(entry)
      source, slug = split_registry_id(entry)

      CatalogSkill.new(
        registry_id: entry.id.presence || "#{source}/#{slug}",
        source: source,
        slug: slug,
        title: (entry.name if entry.name.present? && entry.name != slug),
        installs: entry.installs.to_i
      )
    end

    def split_registry_id(entry)
      parts = entry.id.to_s.split("/").reject(&:blank?)
      return [ entry.source, entry.slug ] if parts.size < 2

      [ parts[0..-2].join("/"), parts.last ]
    end
  end
end
