# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module MCP
  # HTTP adapter for the Official MCP Registry (registry.modelcontextprotocol.io).
  #
  # The only place in the app that talks to the registry. Everything it returns
  # is already normalized by ConnectorManifest, so no caller ever sees a raw
  # registry payload — see that class for why that boundary is enforced.
  #
  # ============================ OPERATING ASSUMPTIONS ============================
  #   * The registry publishes NO uptime or data-durability guarantee and is in
  #     preview. Every method here degrades to empty/nil and logs rather than
  #     raising, so a registry outage makes the catalog stale, not the app broken.
  #   * `search` matches SERVER NAME SUBSTRINGS ONLY — not descriptions. It is
  #     therefore useless as the product's search box and is exposed only as a
  #     targeted lookup. Real catalog search runs locally against the mirror that
  #     #each_updated_since fills.
  #   * The API path is `/v0.1`. A legacy `/v0` still answers but is absent from
  #     the published OpenAPI spec; do not build on it.
  #   * Server names contain slashes ("io.github.owner/server") and MUST be
  #     URL-encoded into the path.
  class ConnectorRegistryClient
    # Raised when a page request fails part-way through a walk. Distinguishing
    # this from "no more pages" is the difference between a mirror that is small
    # and one that is broken.
    class WalkInterrupted < StandardError; end

    DEFAULT_BASE_URL = "https://registry.modelcontextprotocol.io"
    API_PREFIX = "/v0.1"

    # Generous because a walk crosses ~200 pages and the registry's tail latency
    # is real: pages that time out at 15s return ~120KB fine when given longer.
    # One slow page must not end a whole sync.
    LIST_TIMEOUT = 45
    FETCH_TIMEOUT = 10
    PAGE_LIMIT = 100

    # A page is retried before the walk gives up, because a single transient
    # timeout part-way through would otherwise discard the rest of the registry.
    PAGE_ATTEMPTS = 3
    RETRY_DELAY = 2

    # Backstop for a full walk, so a registry paging bug cannot spin forever.
    # At PAGE_LIMIT this is an order of magnitude above the registry's present
    # population (~10k servers as of mid-2026).
    MAX_PAGES = 2_000

    class << self
      # One server version, normalized. `version` accepts an exact version or
      # the special value "latest".
      #
      # Used at INSTALL time even though the mirror already holds a copy: an
      # install must never be built from a stale manifest.
      #
      # @return [Hash, nil] normalized manifest, or nil when unavailable
      def fetch(name, version: "latest")
        return nil if name.blank?

        path = "#{API_PREFIX}/servers/#{encode(name)}/versions/#{encode(version)}"
        entry = get_json(uri_for(path), timeout: FETCH_TIMEOUT)
        return nil if entry.blank?

        ConnectorManifest.normalize(entry)
      rescue StandardError => e
        Rails.logger.error("[ConnectorRegistry] Fetch failed for #{name}@#{version}: #{e.message}")
        nil
      end

      # Targeted name lookup. NOT the product's search — see the class notes.
      # @return [Array<Hash>] normalized manifests
      def search(query, limit: 50)
        return [] if query.blank?

        (page(search: query, limit: limit) || {}).fetch(:manifests, [])
      end

      # Walks every server changed since `timestamp`, yielding normalized
      # manifests one page at a time. This is the mirror's sync path.
      #
      # `updated_since` makes the sync idempotent and gap-tolerant: running it
      # twice, or missing a day, both converge. It also forces the registry to
      # include DELETED servers, which is what lets the mirror learn that a
      # connector was pulled for moderation — pass a timestamp to see deletions,
      # omit it for a first full build.
      #
      # @yield [Array<Hash>] a page of normalized manifests
      # @return [Integer] number of manifests yielded
      # @raise [WalkInterrupted] when a page request fails mid-walk
      def each_updated_since(timestamp = nil)
        cursor = nil
        seen = 0

        MAX_PAGES.times do
          # version=latest: without it the registry returns EVERY version of
          # every server, so one page can carry the same server several times —
          # which the mirror stores by name and which a catalog must not show as
          # separate entries.
          result = page(updated_since: timestamp&.utc&.iso8601(3), cursor: cursor, limit: PAGE_LIMIT,
                        version: "latest")
          # A failed request is NOT the end of the registry. Treating it as one
          # silently truncates the mirror and reports success — a 200-server
          # catalog and a 19,000-server catalog cut short look identical from
          # the outside. The caller has to know the walk did not finish.
          raise WalkInterrupted, "registry stopped answering after #{seen} servers" if result.nil?

          manifests = result[:manifests]
          break if manifests.empty?

          yield manifests
          seen += manifests.size
          cursor = result[:next_cursor]
          break if cursor.blank?
        end

        seen
      end

      private

      # @return [Hash, nil] {manifests:, next_cursor:}, or nil when the request failed
      def page(**params)
        query = params.compact.transform_keys(&:to_s)
        uri = uri_for("#{API_PREFIX}/servers", query)

        PAGE_ATTEMPTS.times do |attempt|
          body = get_json(uri, timeout: LIST_TIMEOUT)
          next sleep_before_retry(attempt) if body.nil?
          return { manifests: [], next_cursor: nil } if body.blank?

          return {
            manifests: Array(body["servers"]).filter_map { |entry| safe_normalize(entry) },
            next_cursor: body.dig("metadata", "nextCursor")
          }
        end

        nil
      end

      # No delay under test: the failures there are synthetic and immediate, and
      # sleeping through them would only slow the suite.
      def sleep_before_retry(attempt)
        return if Rails.env.test? || attempt >= PAGE_ATTEMPTS - 1

        sleep(RETRY_DELAY * (attempt + 1))
      end

      # One malformed entry must not abort a whole sync page: the registry is in
      # preview and a single publisher's bad record is not a reason to stop
      # mirroring everyone else.
      def safe_normalize(entry)
        ConnectorManifest.normalize(entry)
      rescue StandardError => e
        Rails.logger.warn("[ConnectorRegistry] Skipped unnormalizable entry: #{e.message}")
        nil
      end

      def uri_for(path, query = nil)
        uri = URI.join(base_url, path)
        uri.query = URI.encode_www_form(query) if query.present?
        uri
      end

      # Slashes in server names are path data, not separators.
      def encode(value)
        URI.encode_www_form_component(value.to_s).gsub("+", "%20")
      end

      def get_json(uri, timeout:)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                       open_timeout: timeout, read_timeout: timeout) do |http|
          http.get(uri.request_uri, "Accept" => "application/json")
        end
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError => e
        Rails.logger.error("[ConnectorRegistry] GET #{uri} failed: #{e.message}")
        nil
      end

      def base_url
        Settings.mcp_registry&.base_url.presence || DEFAULT_BASE_URL
      end
    end
  end
end
