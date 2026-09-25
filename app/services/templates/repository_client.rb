# frozen_string_literal: true

require "net/http"

module Templates
  # The app-owned adapter for the public templates repository. Two requests per
  # sync: resolve the branch head to a commit, then download the tarball of that
  # exact commit. Pinning the commit first means the mirror always records which
  # reviewed state it holds, even if the branch moves mid-download.
  #
  # The repository is fixed in code: every installation (SaaS, self-hosted, AWS
  # Marketplace) mirrors the same catalog (design D1).
  class RepositoryClient
    REPOSITORY = "AixleHQ/flow-templates"
    BRANCH = "main"
    API_BASE = "https://api.github.com"
    CODELOAD_BASE = "https://codeload.github.com"
    TIMEOUT = 15
    MAX_TARBALL_BYTES = 20.megabytes

    Error = Class.new(StandardError)

    def head_sha
      response = get(URI("#{API_BASE}/repos/#{REPOSITORY}/commits/#{BRANCH}"), accept: "application/vnd.github.sha")
      sha = response.body.to_s.strip
      raise Error, "unexpected commit id from GitHub: #{sha.first(80).inspect}" unless sha.match?(/\A\h{40}\z/)

      sha
    end

    def tarball(sha)
      response = get(URI("#{CODELOAD_BASE}/#{REPOSITORY}/tar.gz/#{sha}"), accept: "application/x-gzip")
      body = response.body.to_s
      raise Error, "tarball is larger than #{MAX_TARBALL_BYTES} bytes" if body.bytesize > MAX_TARBALL_BYTES

      body
    end

    private

    def get(uri, accept:)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Aixle/1.0"
      request["Accept"] = accept
      # The deployment's optional public-read token, never a tenant's installation
      # token (same rule as Skills::GithubSkillTree).
      token = Settings.github.read_token.presence
      request["Authorization"] = "Bearer #{token}" if token && uri.host == URI(API_BASE).host

      response = http.request(request)
      raise Error, "GET #{uri} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error, "GET #{uri} failed: #{e.message}"
    end
  end
end
