# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Skills
  # Transport for skills.sh. Nothing here knows about Skill records — it speaks
  # HTTP and returns hashes, so the catalog sync and the installer can share it.
  #
  # ONLY TWO ENDPOINTS ARE REACHABLE, both unauthenticated:
  #
  #   GET /api/search?q=<≥2 chars>&limit=<≤200>[&owner=]
  #       → { query, searchType, skills: [{ id, skillId, name, source, installs }] }
  #       Ordered by fuzzy relevance, NOT by installs. Carries no description.
  #       A shorter query answers 400, so short input never leaves this process.
  #
  #   GET /api/download/<owner>/<repo>/<skill>
  #       → { files: [{ path, contents }], hash }
  #       404 { "error": "not_found" } for anything the registry does not carry.
  #
  # The documented `/api/v1` surface (leaderboard with all-time/trending/hot views,
  # curated list, security audits) authenticates with a Vercel OIDC token minted
  # per Vercel project and issues no keys to anyone else, so it is unavailable to
  # this deployment. There is no public list endpoint of any kind — hence the
  # seeded sweep in Skills::CatalogSync rather than a page walk.
  #
  # skills.sh's terms encourage "caching results on your own infrastructure" while
  # rate-limiting per IP, which is what makes the mirror legitimate; robots.txt
  # disallows crawling /api/, so nothing here is driven by a crawler.
  class RegistryClient
    BASE = "https://www.skills.sh/api"
    # The audit host the skills CLI itself queries before an install
    # (vercel-labs/skills src/telemetry.ts). Public and unauthenticated, unlike the
    # `/api/v1/skills/audit/...` endpoint the docs describe.
    AUDIT_URL = "https://add-skill.vercel.sh/audit"
    SEARCH_TIMEOUT = 5
    DOWNLOAD_TIMEOUT = 10
    AUDIT_TIMEOUT = 5
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 200
    MIN_QUERY_LENGTH = 2

    # `Entry`, not `Skill`: inside `module Skills` a constant named `Skill` would
    # shadow the model for every reader of this file.
    Entry = Struct.new(:id, :slug, :name, :source, :installs, keyword_init: true)

    # `content_hash`, not `hash`: a struct member called `hash` overrides
    # Object#hash and quietly breaks the object as a Hash key.
    Bundle = Struct.new(:files, :content_hash, keyword_init: true) do
      # Third-party JSON: `files` has been typed as an array by the CLI, but nothing
      # stops the endpoint from returning an object or a string, and a TypeError here
      # would escape into the middle of a sweep.
      def skill_md
        return nil unless files.is_a?(Array)

        entry = files.find do |file|
          file.is_a?(Hash) && (file["path"] == "SKILL.md" || file["path"].to_s.end_with?("/SKILL.md"))
        end
        entry && entry["contents"].presence
      end
    end

    class << self
      # @return [Array<Entry>] empty on any failure — a catalog page must render
      #   even when upstream is down.
      def search(query, limit: DEFAULT_LIMIT, owner: nil)
        query = query.to_s.strip
        return [] if query.length < MIN_QUERY_LENGTH

        params = { q: query, limit: limit.clamp(1, MAX_LIMIT) }
        params[:owner] = owner if owner.present?

        uri = URI("#{BASE}/search")
        uri.query = URI.encode_www_form(params)

        response = get(uri, timeout: SEARCH_TIMEOUT)
        return [] unless response.is_a?(Net::HTTPSuccess)

        entries(JSON.parse(response.body))
          .reject { |s| s["isDuplicate"] }
          .map { |s| build_entry(s) }
      rescue StandardError => e
        Rails.logger.error("[Skills::RegistryClient] Search failed for #{query.inspect}: #{e.message}")
        []
      end

      # @param source [String] "owner/repo"
      # @param slug [String] skill name within the repo
      # @return [Bundle, nil] nil when the registry does not carry it
      def download(source, slug)
        return nil if source.blank? || slug.blank?

        response = get(URI("#{BASE}/download/#{source}/#{slug}"), timeout: DOWNLOAD_TIMEOUT)
        return nil unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body)
        files = body["files"]
        return nil if files.blank?

        Bundle.new(files: files, content_hash: body["hash"])
      rescue StandardError => e
        Rails.logger.warn("[Skills::RegistryClient] Download failed for #{source}/#{slug}: #{e.message}")
        nil
      end

      # Third-party security audits for skills in one repository, batched.
      #
      #   audits("anthropics/skills", %w[pdf frontend-design])
      #   # => { "pdf" => { "snyk" => { "risk" => "high", "analyzedAt" => "..." },
      #   #                 "socket" => { "risk" => "safe", "score" => 90, ... } }, ... }
      #
      # Providers genuinely disagree (snyk has flagged skills the others call safe),
      # so the whole per-provider map is returned rather than a single verdict.
      # Absence of an audit is not a clean bill of health — it means nobody looked.
      #
      # @return [Hash] empty when unavailable; an audit lookup must never block a
      #   catalog page or an install.
      def audits(source, slugs)
        slugs = Array(slugs).compact.uniq
        return {} if source.blank? || slugs.empty?

        uri = URI(AUDIT_URL)
        uri.query = URI.encode_www_form(source: source, skills: slugs.join(","))

        response = get(uri, timeout: AUDIT_TIMEOUT)
        return {} unless response.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(response.body)
        parsed.is_a?(Hash) ? parsed : {}
      rescue StandardError => e
        Rails.logger.warn("[Skills::RegistryClient] Audit lookup failed for #{source}: #{e.message}")
        {}
      end

      private

      # The endpoint has been observed returning a bare array, a `skills` key, and
      # a `data` key across its own history; all three are cheap to accept.
      def entries(body)
        return body if body.is_a?(Array)

        body["skills"] || body["data"] || body["results"] || []
      end

      def build_entry(raw)
        slug = raw["slug"].presence || raw["skillId"].presence || raw["name"]
        Entry.new(
          id: raw["id"],
          slug: slug,
          name: raw["name"].presence || slug,
          source: raw["source"],
          installs: (raw["installs"] || raw["install_count"] || 0).to_i
        )
      end

      def get(uri, timeout:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Aixle/1.0"
        request["Accept"] = "application/json"

        http.request(request)
      end
    end
  end
end
