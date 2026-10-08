# frozen_string_literal: true

require "net/http"
require "json"

# The public AixleHQ/flow repository, read anonymously: its star count for the
# docs header and its CHANGELOG.md for /changelog.
#
# Both reads sit on public pages, which GitHub being down, rate-limited or out
# of reach (an installation with no egress) must not break: a failed read gives
# no star count, and the changelog this build shipped with. A failure is cached
# too, for less long, so such an installation does not wait out a timeout on
# every page view.
class OpenSourceRepository
  FULL_NAME = "AixleHQ/flow"
  URL = "https://github.com/#{FULL_NAME}"
  CHANGELOG_URL = "#{URL}/blob/develop/CHANGELOG.md".freeze
  API_URL = "https://api.github.com/repos/#{FULL_NAME}".freeze
  RAW_CHANGELOG_URL = "https://raw.githubusercontent.com/#{FULL_NAME}/develop/CHANGELOG.md".freeze
  BUNDLED_CHANGELOG = Rails.root.join("CHANGELOG.md")

  TIMEOUT = 3
  FRESH_FOR = 1.hour
  RETRY_AFTER = 10.minutes
  MAX_BYTES = 1.megabyte

  READ_ERRORS = [
    Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError,
    Net::HTTPBadResponse, IOError
  ].freeze

  def self.stars = new.stars
  def self.changelog = new.changelog

  # @return [Integer, nil]
  def stars
    cached("stars") do
      body = get(API_URL, api_headers)
      repository = JSON.parse(body) if body
      count = repository["stargazers_count"] if repository.is_a?(Hash)
      count if count.is_a?(Integer)
    rescue JSON::ParserError
      nil
    end
  end

  # @return [String] CHANGELOG.md in Keep a Changelog form
  def changelog
    cached("changelog") { get(RAW_CHANGELOG_URL)&.force_encoding(Encoding::UTF_8)&.scrub } || BUNDLED_CHANGELOG.read
  end

  private

  def cached(name)
    key = "open_source_repository/#{name}"
    entry = Rails.cache.read(key)
    return entry[:value] if entry

    value = yield
    Rails.cache.write(key, { value: value }, expires_in: value.nil? ? RETRY_AFTER : FRESH_FOR)
    value
  end

  # Optional, and never a customer's installation token — see
  # PublicRepositoryService.
  def api_headers
    token = Settings.github.read_token.presence
    headers = { "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28" }
    headers["Authorization"] = "Bearer #{token}" if token
    headers
  end

  def get(url, headers = {})
    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Aixle/1.0"
      headers.each { |name, value| request[name] = value }
      http.request(request)
    end
    return response.body.to_s.byteslice(0, MAX_BYTES) if response.is_a?(Net::HTTPSuccess)

    Rails.logger.warn("[OpenSourceRepository] #{uri.host} answered #{response.code}")
    nil
  rescue *READ_ERRORS => e
    Rails.logger.warn("[OpenSourceRepository] #{uri.host} request failed: #{e.class}")
    nil
  end
end
