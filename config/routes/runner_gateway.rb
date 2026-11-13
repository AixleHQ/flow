# frozen_string_literal: true

# The runner gateway (docs/design/agent-runtimes/DESIGN.md §6): the JSON API
# aixle-runner calls with a bearer token. Drawn only by the runner gateway's own
# Puma (config/puma_runner_gateway.rb), and by nothing else.
scope "/runner/v1", module: "runner_gateway/v1", as: :runner_gateway_v1, defaults: { format: :json } do
  post "register", to: "registrations#create"
  delete "registration", to: "registrations#destroy"
  post "token", to: "tokens#create"
  post "check-in", to: "check_ins#create"
  post "heartbeat", to: "heartbeats#create"
  get "ops", to: "operations#index"
  post "ops/:id/result", to: "operation_results#create", as: :op_result
  # Public: an operator downloads the binary before the machine has a token.
  # The version may carry dots and a `+`, so neither segment takes a format.
  get "releases/:version/checksums", to: "releases#checksums", as: :release_checksums,
                                     constraints: { version: %r{[^/]+} }, format: false
  get "releases/:version/:platform", to: "releases#show", as: :release,
                                     constraints: { version: %r{[^/]+}, platform: %r{[^/]+} }, format: false
  # The callback proxy (PROTOCOL.md §5.8): any method reaches the controller,
  # which passes only the allow-listed ones. `format: false` keeps a path such
  # as `store/report.json` whole.
  match "proxy/:route(/*path)", to: "proxies#forward", via: :all, as: :proxy, format: false
end
