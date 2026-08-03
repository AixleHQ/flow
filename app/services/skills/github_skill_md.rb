# frozen_string_literal: true

require "net/http"
require "uri"

module Skills
  # Reads a skill's SKILL.md straight from GitHub raw.
  #
  # WHY THIS EXISTS: descriptions live only inside SKILL.md — the search endpoint
  # returns none — and skills.sh's download endpoint allows **60 requests per hour for
  # the whole deployment** (measured; see RegistryClient::RateLimited), a budget a user
  # installing a skill also spends. Reading frontmatter from raw.githubusercontent.com
  # costs nothing from that budget, which is what makes describing a catalog of
  # thousands of entries possible at all.
  #
  # This is also what the skills CLI itself does: `src/blob.ts` documents the flow as
  # "GitHub Trees API → discover SKILL.md locations; raw.githubusercontent.com → fetch
  # frontmatter to get skill names; skills.sh/api/download → fetch full file contents".
  # We skip the Trees API deliberately — it is api.github.com, capped at 60 requests
  # per hour unauthenticated, so guessing two conventional layouts and accepting a miss
  # is strictly better than spending that budget.
  #
  # Only raw content is fetched, and only when the frontmatter `name` matches the slug
  # we asked for, so a wrong guess cannot return someone else's skill.
  class GithubSkillMd
    RAW_BASE = "https://raw.githubusercontent.com"
    TIMEOUT = 8
    MAX_BYTES = 200_000
    # "owner/repo" — anything else (a bare publisher host, a deeper path) is not ours.
    SOURCE_FORMAT = %r{\A[\w.-]+/[\w.-]+\z}

    class << self
      # @return [String, nil] SKILL.md contents, or nil when no conventional path holds it
      def fetch(source, slug)
        return nil unless source.to_s.match?(SOURCE_FORMAT)
        return nil if slug.blank?

        paths(slug).each do |path|
          content = get(source, path)
          next if content.blank?
          # A guessed path that holds a DIFFERENT skill must not be accepted.
          next unless SkillMarkdown.name(content).to_s == slug

          return content
        end

        nil
      rescue StandardError => e
        Rails.logger.warn("[Skills::GithubSkillMd] #{source}/#{slug} failed: #{e.message}")
        nil
      end

      private

      # The two layouts that actually occur: a `skills/` directory (anthropics/skills,
      # obra/superpowers, shadcn/ui) and skills at the repository root. Repos that nest
      # deeper are left to the download endpoint rather than guessed at.
      def paths(slug)
        candidates = [ "skills/#{slug}/SKILL.md", "#{slug}/SKILL.md" ]
        # Some publishers prefix the registry slug with their own name while the
        # directory is unprefixed (`vercel-react-best-practices` → `react-best-practices`).
        stripped = slug.sub(/\A[a-z0-9]+-/, "")
        candidates << "skills/#{stripped}/SKILL.md" if stripped != slug
        candidates
      end

      def get(source, path)
        uri = URI("#{RAW_BASE}/#{source}/HEAD/#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Aixle/1.0"

        response = http.request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        body = response.body.to_s
        return nil if body.bytesize > MAX_BYTES
        return nil if body.blank? || body.start_with?("<!DOCTYPE", "<html")

        body
      end
    end
  end
end
