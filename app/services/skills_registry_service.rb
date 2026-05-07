# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# SkillsRegistryService
# Integrates with skills.sh API for searching and installing agent skills.
#
# Search: GET https://skills.sh/api/search?q=<query>
# Install: Saves metadata + fetches SKILL.md for title/description extraction.
# Actual skill files are installed via `npx skills add` inside the container.
class SkillsRegistryService
  SEARCH_API = "https://skills.sh/api/search"
  GITHUB_RAW_BASE = "https://raw.githubusercontent.com"
  GITHUB_API_BASE = "https://api.github.com"
  SEARCH_TIMEOUT = 5
  FETCH_TIMEOUT = 10

  class RegistryError < StandardError; end

  # Search skills.sh registry
  # @param query [String] search query
  # @return [Array<Hash>] list of skills: { id, name, source, installs }
  def self.search(query)
    return [] if query.blank?

    uri = URI(SEARCH_API)
    uri.query = URI.encode_www_form(q: query)

    response = http_get(uri, timeout: SEARCH_TIMEOUT)
    return [] unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    (data["skills"] || []).map do |s|
      {
        id: s["id"],
        name: s["name"] || s["skillId"],
        source: s["source"],
        installs: s["installs"] || 0
      }
    end
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Search failed: #{e.message}")
    []
  end

  # Register a skill from the registry and create a Skill record.
  # Fetches SKILL.md for title/description only — actual installation
  # into agent containers is handled by `npx skills add` at session start.
  #
  # @param skill_id [String] skills.sh skill ID, e.g. "mantinedev/skills/mantine-form"
  # @param scope [Company, Project] polymorphic scope to attach to
  # @return [Skill] created or updated skill record
  def self.install(skill_id, scope:)
    parts = skill_id.split("/")
    raise RegistryError, "Invalid skill ID: #{skill_id}" if parts.length < 3

    owner = parts[0]
    repo = parts[1]
    skill_name = parts[2..].join("/")
    source = "#{owner}/#{repo}"
    package = "#{source}@#{skill_name}"

    content = fetch_skill_content(owner, repo, skill_name)
    title = extract_title(content, skill_name)
    description = extract_description(content, skill_name)

    existing = scope.skills.find_by(package: package)
    if existing
      existing.update!(title: title, description: description, content: content) if content.present?
      return existing
    end

    raise RegistryError, "Could not fetch SKILL.md for #{skill_id}" if content.blank?

    scope.skills.create!(
      name: skill_name,
      package: package,
      source: source,
      source_url: "https://github.com/#{source}",
      content: content,
      title: title,
      description: description,
      install_count: 0
    )
  end

  # Fetch SKILL.md content from GitHub raw.
  # Tries common paths first; falls back to the Trees API for non-standard layouts.
  def self.fetch_skill_content(owner, repo, skill_name)
    candidate_paths(skill_name).each do |path|
      uri = URI("#{GITHUB_RAW_BASE}/#{owner}/#{repo}/HEAD/#{path}")
      response = http_get(uri, timeout: FETCH_TIMEOUT)
      return response.body if response.is_a?(Net::HTTPSuccess) && response.body.present?
    end

    dynamic_path = resolve_skill_path(owner, repo, skill_name)
    return nil if dynamic_path.blank?

    uri = URI("#{GITHUB_RAW_BASE}/#{owner}/#{repo}/HEAD/#{dynamic_path}")
    response = http_get(uri, timeout: FETCH_TIMEOUT)
    response.is_a?(Net::HTTPSuccess) ? response.body.presence : nil
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Fetch content failed for #{owner}/#{repo}/#{skill_name}: #{e.message}")
    nil
  end

  # Locate SKILL.md anywhere in the repo via the GitHub Trees API.
  # Used as a fallback when the skill lives outside the standard directory layout.
  def self.resolve_skill_path(owner, repo, skill_name)
    uri = URI("#{GITHUB_API_BASE}/repos/#{owner}/#{repo}/git/trees/HEAD?recursive=1")
    response = http_get(uri, timeout: FETCH_TIMEOUT)
    return nil unless response.is_a?(Net::HTTPSuccess)

    tree = JSON.parse(response.body).fetch("tree", [])
    entry = tree.find { |item| item["type"] == "blob" && item["path"].end_with?("SKILL.md") && item["path"].include?(skill_name) }
    entry&.dig("path")
  rescue StandardError => e
    Rails.logger.error("[SkillsRegistry] Trees API failed for #{owner}/#{repo}: #{e.message}")
    nil
  end

  def self.candidate_paths(skill_name)
    [
      "skills/#{skill_name}/SKILL.md",
      "#{skill_name}/SKILL.md",
      "src/core-skills/#{skill_name}/SKILL.md",
      "src/skills/#{skill_name}/SKILL.md",
      "src/#{skill_name}/SKILL.md",
      "SKILL.md"
    ]
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
  def self.extract_description(content, _fallback)
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

  def self.http_get(uri, timeout: 5)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = timeout
    http.read_timeout = timeout

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Aixle/1.0"
    request["Accept"] = "application/json"

    http.request(request)
  end
  private_class_method :http_get, :candidate_paths, :resolve_skill_path
end
