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

        prefixed = nil

        paths(slug).each do |path|
          content = read(source, path)
          next if content.blank?
          # A guessed path that holds a DIFFERENT skill must not be accepted.
          return content if SkillMarkdown.matches_slug?(content, slug)

          # The registry sometimes prefixes a publisher's name onto the slug while the
          # file keeps the bare one. Kept as a fallback so an exact match at a later
          # path still wins.
          prefixed ||= content if SkillMarkdown.prefixed_slug?(content, slug)
        end

        prefixed
      rescue StandardError => e
        Rails.logger.warn("[Skills::GithubSkillMd] #{source}/#{slug} failed: #{e.message}")
        nil
      end

      # One raw read of an exact path, with no identity check — the caller decides what
      # counts as a match. Public because GithubSkillTree reads paths it discovered
      # rather than guessed, and there must be exactly one place that knows how this
      # deployment talks to raw.githubusercontent.com.
      #
      # @return [String, nil] the file, or nil for a miss, an HTML error page or an
      #   implausibly large body
      def read(source, path)
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

      private

      # Flat layouts only, in descending order of how often they occur. A guess costs a
      # CDN read and nothing else, so the list is allowed to be a little speculative —
      # but it stays FLAT: repositories that nest their skills (`plugins/<plugin>/skills/
      # <slug>/`, `<group>/skills/<slug>/`, `skills/<group>/<slug>/`) cannot be guessed
      # at all and are resolved by GithubSkillTree, which reads the real tree instead.
      #
      #   skills/<slug>/     anthropics/skills, obra/superpowers, shadcn/ui
      #   <slug>/            repositories holding one skill at the root
      #   .agents/skills/    the Agent Skills spec's own location (clerk/skills)
      #   .claude/skills/    the same layout under the Claude-specific directory
      def paths(slug)
        candidates = [ "skills/#{slug}/SKILL.md", "#{slug}/SKILL.md",
                       ".agents/skills/#{slug}/SKILL.md", ".claude/skills/#{slug}/SKILL.md" ]
        # Some publishers prefix the registry slug with their own name while the
        # directory is unprefixed (`vercel-react-best-practices` → `react-best-practices`).
        stripped = slug.sub(/\A[a-z0-9]+-/, "")
        candidates << "skills/#{stripped}/SKILL.md" if stripped != slug
        candidates
      end
    end
  end
end
