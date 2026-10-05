# frozen_string_literal: true

module Teams
  # Microsoft Graph as the app itself in a customer's tenant
  # (docs/design/teams-integration.md §5.4): thread reads under resource-specific
  # consent, and files once the organization granted file access. One automatic
  # retry on a throttle or a server error, as the Connector client does.
  module GraphClient
    MAX_RETRY_AFTER = 5

    module_function

    def get(tenant_id, path, query = {})
      request(tenant_id, :get, path, query: query)
    end

    def request(tenant_id, method, path, query: {}, body: nil, headers: {}, retried: false)
      url = "#{Config.cloud[:graph]}/v1.0/#{path.delete_prefix('/')}"
      url = "#{url}?#{URI.encode_www_form(query)}" if query.present?
      response = connection.run_request(method, url, body, default_headers(tenant_id).merge(headers))
      if (response.status == 429 || response.status >= 500) && !retried
        wait = response.headers["Retry-After"].to_i.clamp(0, MAX_RETRY_AFTER)
        sleep(wait) if wait.positive?
        return request(tenant_id, method, path, query: query, body: body, headers: headers, retried: true)
      end
      unless response.success?
        raise Error.new("Graph #{method.upcase} #{path}: HTTP #{response.status} #{response.body.to_s.truncate(300)}",
                        status: response.status, retry_after: response.headers["Retry-After"]&.to_i)
      end

      response.body.to_s.empty? ? {} : JSON.parse(response.body)
    end

    def default_headers(tenant_id)
      { "Authorization" => "Bearer #{TokenService.graph_token(tenant_id)}", "Content-Type" => "application/json" }
    end

    def connection
      Faraday.new do |f|
        f.options.open_timeout = 5
        f.options.timeout = 20
      end
    end
  end
end
