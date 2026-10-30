# frozen_string_literal: true

# The runner gateway (docs/design/agent-runtimes/DESIGN.md §6): the JSON API
# aixle-runner calls with a bearer token. Drawn only by the runner gateway's own
# Puma (config/puma_runner_gateway.rb), and by nothing else.
scope "/runner/v1", module: "runner_gateway/v1", as: :runner_gateway_v1, defaults: { format: :json } do
  post "register", to: "registrations#create"
  delete "registration", to: "registrations#destroy"
  post "token", to: "tokens#create"
  get "ops", to: "operations#index"
  post "ops/:id/result", to: "operation_results#create", as: :op_result
end
