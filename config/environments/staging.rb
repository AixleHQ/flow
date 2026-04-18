require_relative "production"

Rails.application.configure do
  # Staging currently follows production defaults unless explicitly overridden here.

  # Override the static asset_host set in production.rb so that assets are always
  # served from the same origin as the page request. This allows the app to be
  # accessed via both the public domain (https://staging.aixle.com) and the
  # internal Kubernetes service URL (http://web.palad-staging.svc.cluster.local:4000)
  # without Vite asset <script>/<link> tags pointing to an unreachable host.
  #
  # Rails accepts a callable for config.asset_host; it receives the asset path
  # and the request object and must return a host string (scheme + host[:port]).
  config.asset_host = lambda do |_source, request|
    next nil unless request

    host = request.host
    port = request.port
    scheme = request.scheme

    default_port = scheme == "https" ? 443 : 80
    port_suffix = port.to_i != default_port ? ":#{port}" : ""

    "#{scheme}://#{host}#{port_suffix}"
  end
end
