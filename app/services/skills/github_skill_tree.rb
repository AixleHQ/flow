# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Skills
  # Resolves a skill's SKILL.md by reading a repository's REAL tree, for the
  # repositories GithubSkillMd cannot guess.
  #
  # WHY GUESSING IS NOT ENOUGH. Measured over 146 live registry entries, the flat path
  # guesses answer 54% and miss 44%, and the misses are not exotic — they are the
  # publishers that carry most of the catalog:
  #
  #   plugins/<plugin>/skills/<slug>/SKILL.md   wshobson/agents (180), aws/agent-toolkit-for-aws (140)
  #   <group>/skills/<slug>/SKILL.md            anthropics/knowledge-work-plugins (212)
  #   skills/<group>/<slug>/SKILL.md            clerk/skills, mattpocock/skills
  #   <ns>/<name>/SKILL.md                      encoredev/skills (encore-database → encore/database)
  #
  # No fixed list of shapes covers those, and a per-skill guess cannot find them at
  # all. One `git/trees?recursive=1` request per REPOSITORY returns every SKILL.md
  # path at once, which is what makes a 212-skill publisher cost one API request
  # instead of being permanently undescribable.
  #
  # BUDGETS, AND WHY THIS IS AN INSTANCE. api.github.com allows 60 requests/hour
  # unauthenticated for the whole deployment (5,000 with a token — see
  # `Settings.github.read_token`), so the tree requests have to be counted and capped
  # for the length of one sweep. That state is per-run, so this is an object the sync
  # owns rather than a class method: the path list and everything read from it are
  # memoized across the run's rows, and a repository is never listed twice.
  #
  # This mirrors what the skills CLI itself does (`vercel-labs/skills` src/blob.ts:
  # "GitHub Trees API → discover SKILL.md locations; raw.githubusercontent.com → fetch
  # frontmatter to get skill names"). GithubSkillMd stays the first choice because it
  # spends no API budget at all.
  class GithubSkillTree
    API_BASE = "https://api.github.com"
    TIMEOUT = 10
    SOURCE_FORMAT = GithubSkillMd::SOURCE_FORMAT
    # Tree listings one run may spend. A quarter of the unauthenticated hourly
    # allowance, because SkillsRegistryService also reaches api.github.com from inside
    # a user's install request and must not find the budget already gone.
    ANONYMOUS_API_BUDGET = 15
    # With a token the ceiling is 5,000/hour, so the limiting factor stops being the
    # allowance and becomes the run's own wall clock. This is what turns "a couple of
    # dozen publishers a week" into "the whole catalog".
    AUTHENTICATED_API_BUDGET = 400
    # Raw reads one repository may cost across a whole run. Resolution is ~1 read per
    # skill (the best-ranked candidate is normally the right one), so this is a
    # backstop against a repository whose directory names match nothing, not a
    # per-skill limit.
    MAX_READS_PER_SOURCE = 250
    # A repository with more SKILL.md files than this is not a publisher, it is a
    # mirror of other people's; ranking the list per slug stops being worth it.
    MAX_TREE_ENTRIES = 2_000
    # Directory names share nothing with the slug beyond this rank, and reading them
    # all would turn one unresolvable skill into hundreds of requests. Relaxed for
    # small repositories, where reading everything is cheap.
    MAX_RANK = 3
    SMALL_REPO = 5

    # How many repositories one run may list, given what this deployment is allowed.
    def self.default_api_budget
      Settings.github.read_token.presence ? AUTHENTICATED_API_BUDGET : ANONYMOUS_API_BUDGET
    end

    # @param api_budget [Integer] tree listings this run may spend
    # @param reader [#read] raw reader, injected so the identity of the HTTP client
    #   this deployment uses lives in exactly one place (GithubSkillMd.read)
    def initialize(api_budget: self.class.default_api_budget, reader: GithubSkillMd)
      @api_budget = api_budget
      @reader = reader
      @paths = {}
      @contents = {}
      @seen_paths = {}
      @reads = Hash.new(0)
      @requests = 0
      @rate_limited = false
    end

    # Interface-identical to GithubSkillMd.fetch, so the backfill can try one and then
    # the other without knowing how either finds anything.
    #
    # @return [String, nil] SKILL.md contents, or nil when the tree is unavailable or
    #   holds nothing that identifies as this slug
    def fetch(source, slug)
      return nil unless source.to_s.match?(SOURCE_FORMAT)
      return nil if slug.blank?

      key = slug.to_s.parameterize
      cache = (@contents[source] ||= {})
      # Reading one path caches it under whatever skill it turned out to hold, so a
      # repository's second, third and hundredth slug are often already answered.
      return cache[key] if cache.key?(key)

      paths = paths_for(source)
      return nil if paths.blank?

      resolve(source, slug, paths, cache, key)
    rescue StandardError => e
      Rails.logger.warn("[Skills::GithubSkillTree] #{source}/#{slug} failed: #{e.message}")
      nil
    end

    # True once GitHub refused us, so the caller can stop offering rows it cannot help.
    def exhausted?
      @rate_limited || @requests >= @api_budget
    end

    private

    def resolve(source, slug, paths, cache, key)
      prefixed = nil

      candidates(paths, slug).each do |path|
        break if @reads[source] >= MAX_READS_PER_SOURCE
        next unless (@seen_paths[source] ||= Set.new).add?(path)

        @reads[source] += 1
        content = @reader.read(source, path)
        next if content.blank?

        # Cache by what the file says it is, not by what we hoped it was.
        published = SkillMarkdown.name(content)
        cache[published.parameterize] = content if published.present?
        return content if SkillMarkdown.matches_slug?(content, slug)

        # Held back rather than returned: an exact match further down the list must
        # still win over a publisher-prefixed guess.
        prefixed ||= content if SkillMarkdown.prefixed_slug?(content, slug)
      end

      # Remembered either way, so a second pass over the same row costs nothing.
      cache[key] = prefixed
    end

    def paths_for(source)
      return @paths[source] if @paths.key?(source)

      @paths[source] = exhausted? ? nil : list(source)
    end

    # Paths worth reading for this slug, best first.
    #
    # The directory holding a SKILL.md is only ever a HINT — the authoritative
    # identity is the frontmatter `name`, which is what the registry slug is derived
    # from upstream. So this orders reads; it never decides a match.
    def candidates(paths, slug)
      # Registry slugs are sometimes plugin-namespaced (`stitch::react-components`)
      # while the directory carries only the skill part. Split BEFORE parameterising —
      # `parameterize` turns `::` into `-` and the namespace becomes unfindable.
      tail = slug.to_s.split(/::?/).last.to_s.parameterize
      slug = slug.to_s.parameterize
      limit = paths.size <= SMALL_REPO ? Float::INFINITY : MAX_RANK

      paths.map { |path| [ rank(path, slug, tail), path ] }
           .select { |score, _path| score <= limit }
           .sort_by { |score, path| [ score, path.count("/"), path ] }
           .map(&:last)
    end

    def rank(path, slug, tail)
      dir = File.basename(File.dirname(path)).parameterize
      return 0 if dir == slug
      return 1 if dir == tail
      # `encore-database` published from `encore/database/`, `json-render-react` from
      # `skills/react/` — the publisher prefixes the registry name, not the directory.
      return 2 if slug.end_with?("-#{dir}")
      return 3 if dir.end_with?("-#{slug}")

      4
    end

    def list(source)
      @requests += 1
      response = get(URI("#{API_BASE}/repos/#{source}/git/trees/HEAD?recursive=1"))

      if rate_limited?(response)
        # Being throttled is not "this repository has no skills": remember it so the
        # rest of the run stops asking, and leave every unresolved row for next time.
        @rate_limited = true
        Rails.logger.warn("[Skills::GithubSkillTree] GitHub API rate limit reached; skipping tree lookups")
        return nil
      end
      return nil unless response.is_a?(Net::HTTPSuccess)

      entries = JSON.parse(response.body)["tree"]
      return nil unless entries.is_a?(Array)

      # A truncated listing is still worth using: GitHub caps the recursive form, and
      # half a publisher's skills described beats none.
      entries.filter_map { |entry| entry["path"] if skill_md?(entry) }.first(MAX_TREE_ENTRIES)
    rescue StandardError => e
      Rails.logger.warn("[Skills::GithubSkillTree] Tree listing failed for #{source}: #{e.message}")
      nil
    end

    def skill_md?(entry)
      entry.is_a?(Hash) && entry["type"] == "blob" && entry["path"].to_s.end_with?("SKILL.md")
    end

    # 403 with the budget spent and 429 are both "come back later"; a 403 with quota
    # remaining is something else (a blocked repository) and must not stop the run.
    def rate_limited?(response)
      return true if response.is_a?(Net::HTTPTooManyRequests)
      return false unless response.is_a?(Net::HTTPForbidden)

      response["x-ratelimit-remaining"].to_i.zero?
    end

    def get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Aixle/1.0"
      request["Accept"] = "application/vnd.github+json"
      # Optional, and deliberately NOT a customer's installation token: this reads
      # arbitrary public repositories on the deployment's behalf, which is not
      # something any tenant's GitHub App installation grants or should pay for.
      token = Settings.github.read_token.presence
      request["Authorization"] = "Bearer #{token}" if token

      http.request(request)
    end
  end
end
