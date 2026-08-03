# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Skills
  # Resolves a skill published outside GitHub, via RFC 8615 well-known discovery.
  #
  # WHY THIS EXISTS
  # A skills.sh id is usually "owner/repo/slug", but a publisher hosting its own
  # skills has a two-segment id — `open.feishu.cn/lark-doc` (519k installs). For
  # those, `/api/download/<owner>/<repo>/<skill>` has no third path segment to fill
  # and answers 404, and the GitHub fallback cannot apply. The skills CLI reaches
  # them through discovery instead (`src/providers/wellknown.ts`), which is what this
  # reproduces:
  #
  #   GET https://<host>/.well-known/agent-skills/index.json   (preferred)
  #   GET https://<host>/.well-known/skills/index.json         (legacy, still in use)
  #
  # Index formats, both live:
  #   v0.1.0 — { skills: [{ name, description, files: ["SKILL.md", …] }] }
  #            file URLs are <base>/<name>/<file>
  #   v0.2.0 — { skills: [{ name, type: "skill-md"|"archive", description, url, digest }] }
  #            `skill-md` is fetched directly; `archive` is out of scope here, since
  #            unpacking a remote zip is a much larger trust decision than reading
  #            one markdown file.
  #
  # SECURITY: the host comes from a registry id, i.e. from data we do not control, so
  # this is a request to an attacker-influenceable URL. Guards: https only, the host
  # must be a plain dotted hostname (no userinfo, port, path, IP literal, or
  # loopback/internal name), one redirect-free GET per attempt with short timeouts,
  # and a byte cap on every response. Nothing here executes or unpacks anything.
  class WellKnownResolver
    WELL_KNOWN_PATHS = %w[.well-known/agent-skills .well-known/skills].freeze
    INDEX_FILE = "index.json"
    TIMEOUT = 5
    MAX_INDEX_BYTES = 2_000_000
    MAX_SKILL_BYTES = 500_000
    # A hostname, not an address: at least two dot-separated labels, no port, no path.
    HOSTNAME = /\A(?!-)[a-z0-9-]+(\.(?!-)[a-z0-9-]+)+\z/
    BLOCKED_HOSTS = %w[localhost].freeze
    BLOCKED_SUFFIXES = %w[.localhost .local .internal .localdomain].freeze

    class << self
      # @param source [String] the publisher host, e.g. "open.feishu.cn"
      # @param slug [String] the skill name within that publisher's index
      # @return [String, nil] SKILL.md contents, or nil when it cannot be resolved
      def fetch_skill_md(source, slug)
        host = normalize_host(source)
        return nil if host.blank? || slug.blank?

        WELL_KNOWN_PATHS.each do |path|
          base = "https://#{host}/#{path}"
          entry = find_entry(base, slug)
          next if entry.blank?

          content = fetch_entry_content(base, entry, slug)
          return content if content.present?
        end

        nil
      rescue StandardError => e
        Rails.logger.warn("[Skills::WellKnownResolver] #{source}/#{slug} failed: #{e.message}")
        nil
      end

      # A source is well-known-resolvable when it is a bare host rather than an
      # "owner/repo" coordinate.
      def resolvable?(source)
        normalize_host(source).present?
      end

      private

      def normalize_host(source)
        host = source.to_s.strip.downcase
        return nil if host.include?("/") || host.include?("@") || host.include?(":")
        return nil unless host.match?(HOSTNAME)
        return nil if BLOCKED_HOSTS.include?(host) || BLOCKED_SUFFIXES.any? { |s| host.end_with?(s) }
        # Rejects IPv4 literals; a numeric last label is never a real TLD.
        return nil if host.split(".").last.match?(/\A\d+\z/)

        host
      end

      def find_entry(base, slug)
        body = get(URI("#{base}/#{INDEX_FILE}"), max_bytes: MAX_INDEX_BYTES)
        return nil if body.blank?

        index = JSON.parse(body)
        return nil unless index.is_a?(Hash)

        Array(index["skills"]).find { |entry| entry.is_a?(Hash) && entry["name"].to_s == slug }
      rescue JSON::ParserError
        nil
      end

      def fetch_entry_content(base, entry, slug)
        # v0.2.0: an explicit artifact URL, which must stay on the same host so a
        # published index cannot redirect us to somewhere unrelated.
        if entry["url"].present?
          return nil unless entry["type"].to_s == "skill-md"

          url = same_host_uri(entry["url"], base)
          return nil if url.nil?

          return get(url, max_bytes: MAX_SKILL_BYTES)
        end

        # v0.1.0: files are relative to <base>/<name>/.
        return nil unless Array(entry["files"]).include?("SKILL.md")

        get(URI("#{base}/#{slug}/SKILL.md"), max_bytes: MAX_SKILL_BYTES)
      end

      def same_host_uri(url, base)
        uri = URI.parse(url.to_s)
        return nil unless uri.is_a?(URI::HTTPS)
        return nil unless uri.host.to_s.downcase == URI(base).host

        uri
      rescue URI::InvalidURIError
        nil
      end

      # One plain GET. Redirects are NOT followed: a redirect is how a published
      # index would try to send us off-host.
      def get(uri, max_bytes:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Aixle/1.0"

        response = http.request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        body = response.body.to_s
        return nil if body.bytesize > max_bytes
        # A publisher serving its SPA shell for a missing file is a miss, not content.
        return nil if body.start_with?("<!DOCTYPE", "<html")

        body
      end
    end
  end
end
