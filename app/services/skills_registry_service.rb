# frozen_string_literal: true

require "net/http"
require "uri"

# SkillsRegistryService — the install use case for registry skills.
#
# Transport lives in Skills::RegistryClient; this class turns a registry id into a
# Skill record. Resolution order for a skill's SKILL.md:
#
#   1. skills.sh download endpoint — the registry's own answer, whole bundle + hash
#   2. RFC 8615 well-known discovery — for publishers hosting their own skills, whose
#      ids have only two segments ("open.feishu.cn/lark-doc") and which the download
#      endpoint therefore cannot address
#   3. GitHub raw — for repositories the registry does not carry
#
# ONLY PUBLIC ENDPOINTS ARE USABLE. skills.sh's documented `/api/v1` surface
# (leaderboard, curated, search, detail, audits) authenticates with a Vercel OIDC
# token minted per Vercel project and issues no keys to anyone else, so a bearer
# token would only ever get a 401.
class SkillsRegistryService
  GITHUB_RAW_BASE = "https://raw.githubusercontent.com"
  GITHUB_API_BASE = "https://api.github.com"
  FETCH_TIMEOUT = 10
  # Unauthenticated GitHub allows 60 requests/hour for the whole deployment, and this
  # runs inside a web request. The walk is capped and shallow on purpose: an
  # uncapped, nested walk over a large `skills/` tree could hold a Puma worker for
  # minutes and exhaust the hourly budget for everyone.
  MAX_GITHUB_DIRS = 15
  # Hard ceiling on ONE install's resolution, because all of this happens inside a
  # POST. Per-request timeouts alone are not a bound: download (10s) + well-known
  # (3 × 5s) + raw guesses (3 × 8s) + the contents API (10s) + up to 15 raw reads
  # (10s each) is ~200s in the worst case. Puma's default `worker_timeout` is 60s and
  # it kills the WORKER, not the request — so an unlucky install would take every
  # other request on that worker down with it. Fifteen seconds is generous for a
  # resolution that normally takes one round trip.
  RESOLVE_DEADLINE = 15.seconds

  class ResolveTimeout < StandardError; end

  class RegistryError < StandardError; end

  # Search skills.sh. Kept here so existing callers (MCP tools) have one entry point;
  # the transport is Skills::RegistryClient.
  #
  # @return [Array<Hash>] { id:, slug:, name:, source:, installs: }
  def self.search(query, limit: Skills::RegistryClient::DEFAULT_LIMIT)
    Skills::RegistryClient.search(query, limit: limit).map do |entry|
      { id: entry.id, slug: entry.slug, name: entry.name, source: entry.source, installs: entry.installs }
    end
  end

  # Register a skill from the registry and create a Skill record.
  # Actual installation into agent containers happens at session start.
  #
  # @param skill_id [String] e.g. "vercel-labs/agent-skills/next-js-development"
  # @param scope [Project] scope to attach to
  # @param installs [Integer, nil] upstream install count when the caller knows it —
  #   the download endpoint reports none, only search does
  # @return [Skill] created or updated skill record
  def self.install(skill_id, scope:, installs: nil)
    skill_id = skill_id.to_s.strip
    raise RegistryError, "skill_id is required" if skill_id.blank?

    detail = begin
      fetch_skill_detail(skill_id)
    rescue ResolveTimeout
      # Deliberately not "not found": we ran out of time, which is our problem, and a
      # retry may well succeed.
      raise RegistryError, "Took too long to resolve #{skill_id} — try again"
    end
    raise RegistryError, unresolved_message(skill_id) if detail.blank?

    source = detail["source"]
    slug = detail["slug"]
    raise RegistryError, "Invalid skill response for #{skill_id}" if source.blank? || slug.blank?

    package = "#{source}@#{slug}"
    content = detail["content"]
    title = extract_title(content, detail["name"].presence || slug)
    description = Skills::SkillMarkdown.description(content)

    existing = scope.skills.find_by(package: package)
    if existing
      if content.present?
        existing.update!(
          title: title,
          description: description,
          content: content,
          content_hash: detail["content_hash"]
        )
      end
      return existing
    end

    raise RegistryError, "Could not fetch SKILL.md for #{skill_id}" if content.blank?

    scope.skills.create!(
      name: slug,
      package: package,
      source: source,
      source_url: source_url_for(source),
      content: content,
      content_hash: detail["content_hash"],
      title: title,
      description: description,
      install_count: (installs || 0).to_i
    )
  end

  # @param deadline [Time] hard stop for the whole resolution; each source is only
  #   consulted while there is time left, so the total cannot grow with the number of
  #   fallbacks (see RESOLVE_DEADLINE)
  # @return [Hash, nil] { source:, slug:, name:, content:, content_hash: }
  def self.fetch_skill_detail(skill_id, deadline: RESOLVE_DEADLINE.from_now)
    parsed = parse_skill_id(skill_id)
    return nil if parsed.blank?

    source = parsed[:source]
    slug = parsed[:slug]

    bundle = nil
    throttled = false

    if source.include?("/")
      begin
        bundle = Skills::RegistryClient.download(source, slug)
      rescue Skills::RegistryClient::RateLimited
        # 60 downloads per hour for the whole deployment. Being throttled is not the
        # same as the skill not existing, so the free fallbacks still get their turn
        # and the user is told the truth if none of them resolve it.
        throttled = true
      end
    end

    content = bundle&.skill_md
    if content.blank? && time_left?(deadline) && Skills::WellKnownResolver.resolvable?(source)
      content = Skills::WellKnownResolver.fetch_skill_md(source, slug)
    end
    if content.blank? && time_left?(deadline) && github_source?(source)
      content = fetch_skill_md_from_github(source, slug, deadline: deadline)
    end

    if content.blank?
      raise RegistryError, "The skills registry is rate-limiting this deployment — try again in a few minutes" if throttled
      raise ResolveTimeout unless time_left?(deadline)

      return nil
    end

    {
      "source" => source,
      "slug" => slug,
      "name" => Skills::SkillMarkdown.name(content) || slug,
      "content" => content,
      "content_hash" => bundle&.content_hash
    }
  rescue RegistryError, ResolveTimeout
    raise
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Detail fetch failed for #{skill_id}: #{e.message}")
    nil
  end

  # Names the publisher rather than shrugging: a two-segment id from a host that
  # publishes no discovery index is a different problem from a typo.
  def self.unresolved_message(skill_id)
    parsed = parse_skill_id(skill_id)
    source = parsed&.dig(:source)

    if source.present? && !source.include?("/")
      "#{source} does not publish an installable skill index for this skill yet"
    else
      "Skill not found: #{skill_id}"
    end
  end

  # Monotonic where it matters: `Time.current` is fine for a 15-second window, and a
  # clock step during one install is not worth a Process.clock_gettime dance.
  def self.time_left?(deadline)
    Time.current < deadline
  end

  def self.parse_skill_id(skill_id)
    parts = skill_id.to_s.split("/").reject(&:blank?)
    return nil if parts.size < 2

    slug = parts.pop
    source = parts.join("/")
    return nil if slug.blank? || source.blank?

    { source: source, slug: slug }
  end

  def self.github_source?(source)
    source.match?(%r{\A[\w.-]+/[\w.-]+\z})
  end

  # Conventional raw paths first (Skills::GithubSkillMd — shared with the catalog
  # backfill, and free of any rate budget), then one shallow pass over the repo's
  # `skills/` directory listing, bounded by MAX_GITHUB_DIRS. The earlier version also
  # walked each directory's children, multiplying request count by the tree's width.
  def self.fetch_skill_md_from_github(source, slug, deadline: RESOLVE_DEADLINE.from_now)
    content = Skills::GithubSkillMd.fetch(source, slug)
    return content if content.present?
    return nil unless time_left?(deadline)

    list_github_skill_directories(source).first(MAX_GITHUB_DIRS).each do |dir|
      # Checked every iteration: fifteen directories at up to 10s each is the exact
      # shape that would otherwise hold a Puma worker past its liveness timeout.
      break unless time_left?(deadline)

      content = fetch_raw_skill_md(source, "skills/#{dir}/SKILL.md", slug: slug)
      return content if content.present?
    end

    nil
  rescue StandardError => e
    Rails.logger.warn("[SkillsRegistry] GitHub fetch failed for #{source}/#{slug}: #{e.message}")
    nil
  end

  def self.fetch_raw_skill_md(source, path, slug:)
    response = http_get(URI("#{GITHUB_RAW_BASE}/#{source}/#{path.start_with?('HEAD/') ? path : "HEAD/#{path}"}"))
    return nil unless response.is_a?(Net::HTTPSuccess)

    body = response.body
    return nil if body.blank? || body.start_with?("<!DOCTYPE", "<html")
    return body if Skills::SkillMarkdown.matches_slug?(body, slug)

    nil
  end

  def self.list_github_skill_directories(source)
    response = http_get(URI("#{GITHUB_API_BASE}/repos/#{source}/contents/skills"))
    return [] unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).filter_map { |entry| entry["name"] if entry["type"] == "dir" }
  rescue StandardError
    []
  end

  def self.source_url_for(source)
    if github_source?(source)
      "https://github.com/#{source}"
    else
      "https://#{source}"
    end
  end

  # Title from frontmatter or first heading, falling back to a humanised slug.
  def self.extract_title(content, fallback)
    return fallback.tr("-_", " ").titleize if content.blank?

    name = Skills::SkillMarkdown.name(content)
    return name if name.present?

    content[/^#\s+(.+)/, 1] || fallback.tr("-_", " ").titleize
  end

  def self.http_get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = FETCH_TIMEOUT
    http.read_timeout = FETCH_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Aixle/1.0"
    request["Accept"] = "application/json"

    http.request(request)
  end

  private_class_method :time_left?, :parse_skill_id, :github_source?,
                       :fetch_skill_md_from_github, :fetch_raw_skill_md,
                       :list_github_skill_directories, :source_url_for, :http_get,
                       :unresolved_message
end
