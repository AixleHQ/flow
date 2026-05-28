# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# SkillsRegistryService
# Integrates with the skills.sh API (https://www.skills.sh/docs/api).
#
# Search: GET /api/v1/skills/search?q=<query>
# Install: GET /api/v1/skills/{id} — persists SKILL.md metadata in the database.
# Actual skill files are installed via `npx skills add` inside the container.
class SkillsRegistryService
  API_BASE = "https://skills.sh/api/v1"
  PUBLIC_API_BASE = "https://www.skills.sh/api"
  SEARCH_TIMEOUT = 5
  FETCH_TIMEOUT = 10
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
    items = body.is_a?(Array) ? body : (body["data"] || body["results"] || [])
    items.map { |s| map_public_search_skill(s) }
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
    raise RegistryError, "Skills.sh API key is not configured" if api_key.blank?

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

  # Fetch full skill detail from GET /api/v1/skills/{id}.
  def self.fetch_skill_detail(skill_id)
    uri = detail_uri(skill_id)
    response = http_get(uri, timeout: FETCH_TIMEOUT)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Detail fetch failed for #{skill_id}: #{e.message}")
    nil
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
    {
      id: skill["id"],
      slug: skill["slug"] || skill["name"],
      name: skill["name"] || skill["slug"],
      source: skill["source"],
      installs: skill["installs"] || skill["install_count"] || 0
    }
  end

  def self.source_url_for(source)
    if source.match?(%r{\A[\w.-]+/[\w.-]+\z})
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

    if content.start_with?("---")
      parts = content.split("---", 3)
      if parts.length >= 3
        meta = YAML.safe_load(parts[1]) rescue {}
        return meta["name"] || meta["title"] if (meta["name"] || meta["title"]).present?
      end
    end

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
                       :skill_md_content, :source_url_for, :detail_uri, :api_key, :http_get
end
