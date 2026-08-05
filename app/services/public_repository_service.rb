# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Resolves a PUBLIC repository from a url (or an owner/repo pair) without any
# tenant credentials, so a project can attach a repository nobody installed the
# GitHub App on — the OSS case: reading someone else's public code.
#
# WHY THIS EXISTS SEPARATELY FROM Github::RepositoryService. That adapter lists
# what a tenant's App installation can reach and mints installation tokens; it
# structurally cannot see a third party's repository, and pointing it at one
# fails at token minting (`repositories:` rejects anything outside the
# installation with a 422). Public reads therefore go through the deployment's
# own anonymous access, exactly like the skills catalog does
# (Skills::GithubSkillTree) — and, for the same reason spelled out there, a
# tenant's installation token must NEVER be used here.
#
# WHAT THE RESULT IS FOR. `clone_url` is rebuilt from the host allowlist and the
# API's canonical `full_name`, never echoed from user input: it ends up in a
# `git clone` command line inside a session container. `private` repositories are
# rejected rather than reported, because an anonymous clone of one cannot work.
#
# BUDGET. api.github.com allows 60 requests/hour unauthenticated for the whole
# deployment; `Settings.github.read_token` (optional, no scopes needed) raises
# that to 5,000. One request per attach is small next to the catalog sweep, but
# it shares the same allowance — hence the explicit rate-limit error.
class PublicRepositoryService
  class Error < StandardError; end
  # The host is not one we can verify or clone anonymously.
  class UnsupportedHost < Error; end
  # No such repository, or it exists but is not publicly visible (GitHub answers
  # 404 for both, and we cannot tell them apart without credentials).
  class NotFound < Error; end
  # Visible to us but not public — an anonymous clone would fail.
  class NotPublic < Error; end
  # Network failure, rate limit, or an unexpected status.
  class TransportError < Error; end

  GITHUB_API = "https://api.github.com"
  GITLAB_API = "https://gitlab.com/api/v4"
  TIMEOUT = 10
  MAX_BYTES = 256 * 1024
  # Paths GitHub and GitLab hang off a repository url (".../tree/main",
  # ".../-/blob/main/x.rb"). A pasted deep link should still resolve to the
  # repository it points into.
  GITHUB_SUBPATHS = %w[tree blob commits releases issues pull pulls actions wiki].freeze

  Result = Struct.new(:provider, :full_name, :default_branch, :clone_url, :description, keyword_init: true) do
    def to_repository_attributes
      {
        full_name: full_name,
        clone_url: clone_url,
        source_branch: default_branch,
        description: description,
        is_private: false,
        integration_id: nil
      }
    end
  end

  # @param input [String] "https://github.com/rails/rails", "github.com/rails/rails",
  #   "https://gitlab.com/group/sub/app", or a bare "owner/repo" (assumed GitHub).
  # @return [Result]
  # @raise [Error] one of the subclasses above; every message is user-facing.
  def self.resolve(input)
    new.resolve(input)
  end

  def resolve(input)
    provider, full_name = parse(input)

    case provider
    when "github" then resolve_github(full_name)
    when "gitlab" then resolve_gitlab(full_name)
    end
  end

  private

  # Returns [provider, full_name]. Raises UnsupportedHost for anything we cannot
  # verify — including hosts that merely LOOK like the real ones, since the host
  # decides which API is asked and which host the clone dials.
  def parse(input)
    raw = input.to_s.strip
    raise UnsupportedHost, "Enter a GitHub or GitLab repository url" if raw.blank?

    return parse_bare(raw) unless raw.include?("/") && raw.match?(%r{\A(?:[a-z][a-z0-9+.-]*://|(?:www\.)?(?:github|gitlab)\.com/)}i)

    uri = parse_uri(raw)
    provider = Repository::PUBLIC_HOSTS[uri.host.to_s.downcase.delete_prefix("www.")]
    raise UnsupportedHost, "Only github.com and gitlab.com repositories can be added by url" if provider.blank?
    raise UnsupportedHost, "Repository url must use https" unless uri.scheme.nil? || uri.scheme == "https"

    [ provider, full_name_from_path(provider, uri.path) ]
  end

  def parse_uri(raw)
    URI.parse(raw.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? raw : "https://#{raw}")
  rescue URI::InvalidURIError
    raise UnsupportedHost, "#{raw} is not a valid repository url"
  end

  def parse_bare(raw)
    segments = raw.split("/").reject(&:blank?)
    raise UnsupportedHost, "Enter a GitHub or GitLab repository url" unless segments.size == 2

    [ "github", validated_full_name(segments.join("/")) ]
  end

  def full_name_from_path(provider, path)
    segments = path.to_s.split("/").reject(&:blank?)
    segments = truncate_subpath(provider, segments)
    segments[-1] = segments[-1].delete_suffix(".git") if segments.any?

    raise UnsupportedHost, "Repository url must include an owner and a repository" if segments.size < 2

    validated_full_name(segments.join("/"))
  end

  # GitHub deep links are always owner/repo/<verb>/…; GitLab puts everything past
  # the project behind a "/-/" separator, which also makes subgroups safe to keep.
  def truncate_subpath(provider, segments)
    if provider == "gitlab"
      dash = segments.index("-")
      return dash ? segments[0...dash] : segments
    end

    return segments[0, 2] if segments.size > 2 && GITHUB_SUBPATHS.include?(segments[2])

    segments[0, 2]
  end

  def validated_full_name(full_name)
    unless full_name.match?(%r{\A[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)+\z})
      raise UnsupportedHost, "#{full_name} is not a valid owner/repo name"
    end

    full_name
  end

  def resolve_github(full_name)
    data = get_json(URI.parse("#{GITHUB_API}/repos/#{full_name}"), github_headers, "GitHub")
    raise NotPublic, "#{full_name} is a private repository — connect a GitHub integration instead" if data["private"]

    canonical = data["full_name"].presence || full_name
    Result.new(
      provider: "github",
      full_name: canonical,
      default_branch: data["default_branch"].presence || "main",
      clone_url: "https://github.com/#{canonical}.git",
      description: data["description"].presence
    )
  end

  def resolve_gitlab(full_name)
    uri = URI.parse("#{GITLAB_API}/projects/#{CGI.escape(full_name)}")
    data = get_json(uri, { "Accept" => "application/json" }, "GitLab")

    unless data["visibility"] == "public"
      raise NotPublic, "#{full_name} is not a public project — connect a GitLab integration instead"
    end

    canonical = data["path_with_namespace"].presence || full_name
    Result.new(
      provider: "gitlab",
      full_name: canonical,
      default_branch: data["default_branch"].presence || "main",
      clone_url: "https://gitlab.com/#{canonical}.git",
      description: data["description"].presence
    )
  end

  def github_headers
    headers = {
      "Accept" => "application/vnd.github+json",
      "X-GitHub-Api-Version" => "2022-11-28"
    }
    # Optional, and deliberately NOT a customer's installation token — see the
    # class comment and Settings.github.read_token.
    token = Settings.github.read_token.presence
    headers["Authorization"] = "Bearer #{token}" if token
    headers
  end

  def get_json(uri, headers, label)
    response = get(uri, headers)

    case response
    when Net::HTTPSuccess
      parse_json(response, label)
    when Net::HTTPNotFound
      raise NotFound, "Repository not found on #{label}, or it is not public"
    when Net::HTTPTooManyRequests
      raise TransportError, "#{label} rate limit reached — try again in a few minutes"
    when Net::HTTPForbidden
      raise TransportError, forbidden_message(response, label)
    else
      raise TransportError, "#{label} returned #{response.code} for this repository"
    end
  end

  def forbidden_message(response, label)
    return "#{label} rate limit reached — try again in a few minutes" if response["x-ratelimit-remaining"].to_i.zero?

    "#{label} refused to describe this repository"
  end

  def parse_json(response, label)
    body = response.body.to_s.byteslice(0, MAX_BYTES)
    parsed = JSON.parse(body)
    raise TransportError, "#{label} returned an unexpected response" unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError
    raise TransportError, "#{label} returned an unreadable response"
  end

  def get(uri, headers)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Aixle/1.0"
    headers.each { |key, value| request[key] = value }

    http.request(request)
  rescue Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, IOError => e
    Rails.logger.warn("[PublicRepositoryService] #{uri.host} request failed: #{e.class}")
    raise TransportError, "Could not reach #{uri.host}"
  end
end
