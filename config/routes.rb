# frozen_string_literal: true

# Each process draws only the routes it serves (docs/design/agent-runtimes/DESIGN.md
# §6.1). AIXLE_PROCESS_MODE is set by the process's own Puma config, never by
# the deployment: config/puma_runner_gateway.rb sets it to `runner_gateway`, and
# that process routes /runner/v1/* and /up only. Every other process routes the
# rest, MCP included, and answers 404 on /runner/v1/*.
Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  if ENV["AIXLE_PROCESS_MODE"] == "runner_gateway"
    draw :runner_gateway
  else
    draw :mcp
    draw :web
  end
end
