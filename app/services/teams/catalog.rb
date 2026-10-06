# frozen_string_literal: true

module Teams
  # Publishes the deployment's Teams app to an organization's app catalog as the
  # administrator who approved the connection, so nobody downloads and uploads
  # the package by hand. Microsoft offers this only to a signed-in administrator
  # (delegated AppCatalog.ReadWrite.All), never to the app itself. A failure
  # leaves the connection working and the package to download instead.
  module Catalog
    module_function

    def publish!(integration, admin_token)
      existing = find(admin_token)
      app = if existing.nil?
        request(admin_token, :post, "appCatalogs/teamsApps")
      elsif existing_version(existing) == AppPackage::VERSION
        existing
      else
        request(admin_token, :post, "appCatalogs/teamsApps/#{existing['id']}/appDefinitions")
        existing
      end
      record(integration, "catalog_app_id" => app["teamsAppId"] || app["id"], "catalog_version" => AppPackage::VERSION,
                          "catalog_published_at" => Time.current.iso8601, "catalog_error" => nil)
    rescue Error => e
      Rails.logger.warn("[Teams::Catalog] integration ##{integration.id}: #{e.message}")
      record(integration, "catalog_error" => e.status.to_i == 403 ? "forbidden" : "failed")
    end

    def find(admin_token)
      query = { "$filter" => "externalId eq '#{AppPackage.manifest_id}'", "$expand" => "appDefinitions($select=version)" }
      Array(request(admin_token, :get, "appCatalogs/teamsApps", query: query)["value"]).first
    end

    def existing_version(app)
      versions = Array(app["appDefinitions"]).map { |definition| definition["version"].to_s }
      versions.select { |version| Gem::Version.correct?(version) }.max_by { |version| Gem::Version.new(version) }
    end

    def record(integration, values)
      integration.update!(settings: integration.settings.to_h.merge(values))
      integration
    end

    def request(admin_token, method, path, query: nil)
      url = "#{Config.cloud[:graph]}/v1.0/#{path}"
      url = "#{url}?#{URI.encode_www_form(query)}" if query
      headers = { "Authorization" => "Bearer #{admin_token}" }
      body = nil
      if method == :post
        headers["Content-Type"] = "application/zip"
        body = AppPackage.zip
      end
      response = Faraday.new { |f| f.options.timeout = 30 }.run_request(method, url, body, headers)
      unless response.success?
        raise Error.new("Graph #{method.upcase} #{path}: HTTP #{response.status} #{response.body.to_s.truncate(300)}",
                        status: response.status)
      end

      response.body.to_s.empty? ? {} : JSON.parse(response.body)
    rescue Faraday::Error => e
      raise Error.new("Graph #{method.upcase} #{path}: #{e.message}", status: 503)
    rescue JSON::ParserError
      {}
    end
  end
end
