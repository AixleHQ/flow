# frozen_string_literal: true

require "net/http"
require "timeout"

class ProjectMemorySourceVerifier
  MAX_RESPONSE_BYTES = 32_768

  def self.build
    new
  end

  def initialize(timeout_seconds: 3)
    @timeout_seconds = timeout_seconds
  end

  def current?(project:, sources:)
    return false unless sources.is_a?(Array) && sources.size.between?(1, 3)

    Timeout.timeout(@timeout_seconds) do
      sources.all? do |source|
        next false unless valid_source?(source)

        repository = Repository.for_project(project).find_by(id: source["repository_id"])
        next false unless repository&.provider == "github"
        next false if repository.integration && !repository.integration.active?

        latest_file_revision(repository, source["path"]) == source["revision"]
      end
    end
  rescue StandardError
    false
  end

  private

  def valid_source?(source)
    return false unless source.is_a?(Hash)

    path = source["path"]
    path.is_a?(String) && path.length.between?(1, 300) &&
      !path.start_with?("/") && !path.match?(/[\x00-\x1f\\]/) &&
      (path.split("/") & %w[. ..]).empty? &&
      source["revision"].to_s.match?(/\A[0-9a-f]{40}\z/)
  end

  # A file's last commit avoids invalidating a finding when unrelated files change.
  # https://docs.github.com/en/rest/commits/commits#list-commits
  def latest_file_revision(repository, path)
    uri = URI("https://api.github.com/repos/#{repository.full_name}/commits")
    uri.query = URI.encode_www_form(sha: repository.source_branch, path: path, per_page: 1)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    if repository.integration
      token = Github::TokenService.new(repository.integration)
        .generate_installation_token(repositories: [ repository.repo_name ])
      request["Authorization"] = "Bearer #{token}"
    end

    body = +""
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 2, write_timeout: 2) do |http|
      http.max_retries = 0
      http.request(request) do |response|
        return nil unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          return nil if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES

          body << chunk
        end
      end
    end
    data = JSON.parse(body)
    data.first["sha"] if data.is_a?(Array) && data.first.is_a?(Hash)
  end
end
