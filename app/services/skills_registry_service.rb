# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "open3"
require "tmpdir"
require "timeout"

# SkillsRegistryService
# Integrates with the skills.sh API (https://www.skills.sh/docs/api).
#
# Search: GET /api/v1/skills/search?q=<query> (authenticated)
#         GET https://www.skills.sh/api/search?q=<query> (public fallback)
# Install: GET /api/v1/skills/{id} (authenticated)
#          GitHub raw + skills CLI (public fallback)
# Actual skill files are installed via `npx skills add` inside the container.
class SkillsRegistryService
  API_BASE = "https://skills.sh/api/v1"
  PUBLIC_API_BASE = "https://www.skills.sh/api"
  GITHUB_RAW_BASE = "https://raw.githubusercontent.com"
  GITHUB_API_BASE = "https://api.github.com"
  SEARCH_TIMEOUT = 5
  FETCH_TIMEOUT = 10
  CLI_INSTALL_TIMEOUT = 120
  SEARCH_LIMIT = 50
  PUBLIC_SEARCH_LIMIT = 100
  MIN_QUERY_LENGTH = 2

  class RegistryError < StandardError; end

  # Search skills.sh registry.
  # @param query [String] search query (minimum 2 characters per API)
  # @param limit [Integer] max results, 1–200 (default 50)
  # @return [Array<Hash>] list of skills: { id, name, source, installs }
  def self.search(query, limit: SEARCH_LIMIT)
    query = query.to_s.strip
    return [] if query.length < MIN_QUERY_LENGTH

    return search_public(query) unless api_key.present?

    uri = URI("#{API_BASE}/skills/search")
    uri.query = URI.encode_www_form(q: query, limit: limit.clamp(1, 200))

    response = http_get(uri, timeout: SEARCH_TIMEOUT)
    return [] unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    (data["data"] || []).reject { |s| s["isDuplicate"] }.map { |s| map_search_skill(s) }
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Search failed: #{e.message}")
    []
  end

  # Unauthenticated fallback using the public skills.sh search endpoint.
  # Used when no API key is configured.
  def self.search_public(query)
    uri = URI("#{PUBLIC_API_BASE}/search")
    uri.query = URI.encode_www_form(q: query, limit: PUBLIC_SEARCH_LIMIT)

    response = http_get(uri, timeout: SEARCH_TIMEOUT)
    return [] unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    items = if body.is_a?(Array)
      body
    else
      body["skills"] || body["data"] || body["results"] || []
    end
    items.reject { |s| s["isDuplicate"] }.map { |s| map_public_search_skill(s) }
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Public search failed: #{e.message}")
    []
  end

  # Register a skill from the registry and create a Skill record.
  # Fetches skill detail (including SKILL.md) from the API — actual installation
  # into agent containers is handled by `npx skills add` at session start.
  #
  # @param skill_id [String] skills.sh skill ID, e.g. "vercel-labs/agent-skills/next-js-development"
  # @param scope [Company, Project] polymorphic scope to attach to
  # @return [Skill] created or updated skill record
  def self.install(skill_id, scope:)
    skill_id = skill_id.to_s.strip
    raise RegistryError, "skill_id is required" if skill_id.blank?

    detail = fetch_skill_detail(skill_id)
    raise RegistryError, "Skill not found: #{skill_id}" if detail.blank?

    source = detail["source"]
    slug = detail["slug"]
    raise RegistryError, "Invalid skill response for #{skill_id}" if source.blank? || slug.blank?

    package = "#{source}@#{slug}"
    content = skill_md_content(detail)
    title = extract_title(content, detail["name"].presence || slug)
    description = extract_description(content)

    existing = scope.skills.find_by(package: package)
    if existing
      existing.update!(title: title, description: description, content: content) if content.present?
      return existing
    end

    raise RegistryError, "Could not fetch SKILL.md for #{skill_id}" if content.blank?

    scope.skills.create!(
      name: slug,
      package: package,
      source: source,
      source_url: source_url_for(source),
      content: content,
      title: title,
      description: description,
      install_count: detail["installs"].to_i
    )
  end

  # Fetch full skill detail (v1 API or public fallback).
  def self.fetch_skill_detail(skill_id)
    if api_key.present?
      fetch_skill_detail_authenticated(skill_id)
    else
      fetch_skill_detail_public(skill_id)
    end
  end

  def self.fetch_skill_detail_authenticated(skill_id)
    uri = detail_uri(skill_id)
    response = http_get(uri, timeout: FETCH_TIMEOUT)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Detail fetch failed for #{skill_id}: #{e.message}")
    nil
  end

  # Public install path: resolve SKILL.md from GitHub or the skills CLI.
  def self.fetch_skill_detail_public(skill_id)
    parsed = parse_skill_id(skill_id)
    return nil if parsed.blank?

    source = parsed[:source]
    slug = parsed[:slug]
    content = fetch_skill_md_from_github(source, slug) if github_source?(source)
    content ||= fetch_skill_md_via_cli(source, slug)

    return nil if content.blank?

    {
      "id" => skill_id,
      "source" => source,
      "slug" => slug,
      "name" => frontmatter_name(content) || slug,
      "installs" => 0,
      "files" => [ { "path" => "SKILL.md", "contents" => content } ]
    }
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Public detail fetch failed for #{skill_id}: #{e.message}")
    nil
  end

  def self.parse_skill_id(skill_id)
    parts = skill_id.split("/")
    return nil if parts.size < 2

    slug = parts.pop
    source = parts.join("/")
    return nil if slug.blank? || source.blank?

    { source: source, slug: slug }
  end

  def self.github_source?(source)
    source.match?(%r{\A[\w.-]+/[\w.-]+\z})
  end

  def self.github_skill_path_guesses(slug)
    guesses = [ slug ]
    guesses << slug.sub(/\Avercel-/, "") if slug.start_with?("vercel-")
    guesses.uniq
  end

  def self.fetch_skill_md_from_github(source, slug)
    github_skill_path_guesses(slug).each do |dir|
      content = fetch_raw_skill_md(source, "skills/#{dir}/SKILL.md", slug: slug)
      return content if content.present?
    end

    list_github_skill_directories(source).each do |dir|
      content = fetch_raw_skill_md(source, "skills/#{dir}/SKILL.md", slug: slug)
      return content if content.present?

      list_github_skill_directories(source, "skills/#{dir}").each do |nested|
        content = fetch_raw_skill_md(source, "skills/#{dir}/#{nested}/SKILL.md", slug: slug)
        return content if content.present?
      end
    end

    nil
  rescue StandardError => e
    Rails.logger.warn("[SkillsRegistry] GitHub fetch failed for #{source}/#{slug}: #{e.message}")
    nil
  end

  def self.fetch_raw_skill_md(source, path, slug:)
    content = fetch_github_raw(source, path)
    return nil if content.blank?
    return content if skill_md_matches_slug?(content, slug)

    nil
  end

  def self.skill_md_matches_slug?(content, slug)
    name = frontmatter_name(content)
    return true if name.present? && name == slug

    false
  end

  def self.fetch_github_raw(source, path)
    uri = URI("#{GITHUB_RAW_BASE}/#{source}/HEAD/#{path}")
    response = http_get(uri, timeout: FETCH_TIMEOUT)
    return nil unless response.is_a?(Net::HTTPSuccess)

    body = response.body
    return nil if body.blank? || body.start_with?("<!DOCTYPE", "<html")

    body
  end

  def self.list_github_skill_directories(source, prefix = "skills")
    uri = URI("#{GITHUB_API_BASE}/repos/#{source}/contents/#{prefix}")
    response = http_get(uri, timeout: FETCH_TIMEOUT)
    return [] unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).filter_map { |entry| entry["name"] if entry["type"] == "dir" }
  rescue StandardError
    []
  end

  def self.fetch_skill_md_via_cli(source, slug)
    skill_md = nil

    Dir.mktmpdir("skills-registry") do |tmpdir|
      env = {
        "HOME" => tmpdir,
        "DISABLE_TELEMETRY" => "1",
        "PATH" => ENV.fetch("PATH", "/usr/bin:/bin")
      }

      _stdout, stderr, status = Timeout.timeout(CLI_INSTALL_TIMEOUT) do
        Open3.capture3(
          env,
          "yarn", "dlx", "skills", "add", source,
          "--skill", slug,
          "-g",
          "-a", "claude-code",
          "--copy", "-y",
          chdir: Rails.root.to_s
        )
      end

      unless status.success?
        Rails.logger.warn("[SkillsRegistry] skills CLI install failed: #{stderr.to_s.truncate(300)}")
        next
      end

      skill_md = Dir.glob(File.join(tmpdir, ".claude/skills/*/SKILL.md")).first
      skill_md = File.read(skill_md) if skill_md.present?
    end

    skill_md.presence
  rescue StandardError => e
    Rails.logger.warn("[SkillsRegistry] skills CLI fetch failed: #{e.message}")
    nil
  end

  def self.frontmatter_name(content)
    return nil if content.blank?
    return nil unless content.start_with?("---")

    parts = content.split("---", 3)
    return nil if parts.length < 3

    meta = YAML.safe_load(parts[1]) rescue {}
    meta["name"].presence || meta["title"].presence
  end

  def self.skill_md_content(detail)
    files = detail["files"]
    return nil if files.blank?

    entry = files.find { |f| f["path"] == "SKILL.md" || f["path"]&.end_with?("/SKILL.md") }
    entry&.dig("contents").presence
  end

  def self.map_search_skill(skill)
    {
      id: skill["id"],
      slug: skill["slug"],
      name: skill["name"] || skill["slug"],
      source: skill["source"],
      installs: skill["installs"] || 0
    }
  end

  def self.map_public_search_skill(skill)
    slug = skill["slug"].presence || skill["skillId"].presence || skill["name"]
    {
      id: skill["id"],
      slug: slug,
      name: skill["name"].presence || slug,
      source: skill["source"],
      installs: skill["installs"] || skill["install_count"] || 0
    }
  end

  def self.source_url_for(source)
    if github_source?(source)
      "https://github.com/#{source}"
    else
      "https://#{source}"
    end
  end

  def self.detail_uri(skill_id)
    encoded_path = skill_id.split("/").map { |segment| URI.encode_uri_component(segment) }.join("/")
    URI("#{API_BASE}/skills/#{encoded_path}")
  end

  # Extract title from SKILL.md frontmatter or first heading
  def self.extract_title(content, fallback)
    return fallback.tr("-_", " ").titleize if content.blank?

    name = frontmatter_name(content)
    return name if name.present?

    first_heading = content[/^#\s+(.+)/, 1]
    first_heading || fallback.tr("-_", " ").titleize
  end

  # Extract description from SKILL.md frontmatter
  def self.extract_description(content)
    return nil if content.blank?

    if content.start_with?("---")
      parts = content.split("---", 3)
      if parts.length >= 3
        meta = YAML.safe_load(parts[1]) rescue {}
        return meta["description"].to_s.strip.truncate(500) if meta["description"].present?
      end
    end

    nil
  end

  def self.api_key
    Settings.skills_sh.api_key.presence
  end

  def self.http_get(uri, timeout: 5)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = timeout
    http.read_timeout = timeout

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Aixle/1.0"
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{api_key}" if api_key.present?

    http.request(request)
  end

  private_class_method :map_search_skill, :map_public_search_skill, :search_public,
                       :fetch_skill_detail_authenticated, :fetch_skill_detail_public,
                       :parse_skill_id, :github_source?, :github_skill_path_guesses,
                       :fetch_skill_md_from_github,
                       :fetch_raw_skill_md, :skill_md_matches_slug?, :fetch_github_raw,
                       :list_github_skill_directories, :fetch_skill_md_via_cli,
                       :frontmatter_name, :skill_md_content, :source_url_for, :detail_uri,
                       :api_key, :http_get
end
