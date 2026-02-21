require "net/http"
require "json"

namespace :rollbar do
  desc "Notify Rollbar of a deployment"
  task :deploy do
    uri = URI(Settings.rollbar.deploy_endpoint)
    headers = { "Content-Type" => "application/json" }
    data = {
      access_token: Settings.rollbar.access_token,
      environment: Rails.env,
      revision: Settings.app.version,
      local_username: "#{Settings.app.last_commiter.name} #{Settings.app.last_commiter.email}"
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.path, headers)
    request.body = data.to_json

    response = http.request(request)
    puts "Rollbar response: #{response.code} #{response.body}"
    unless response.is_a?(Net::HTTPSuccess)
      abort "Failed to notify Rollbar of deployment."
    end
  end
end
