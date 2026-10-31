# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Where this app's own secrets travel under names the list above misses:
  # config_item[value], mcp_server[headers]/[env], connector install values,
  # OAuth `code`, the credential write-back's `files` (whole auth files keyed by
  # path), and anything spelled api_key/apiKey/authorization/credentials.
  :value, :headers, :env, :files, :code, :authorization, :credentials, :config_data, /api[-_]?key/i,
  # Not secret — just enormous. The agent runtimes POST an OTLP envelope to
  # /api/v1/internal/usage_statistics every couple of seconds per live session, and
  # Rails logs the whole parsed structure on every one of them. In production that
  # was the single largest thing in the web logs, at tens of kilobytes a line.
  :resourceMetrics, :resourceLogs
]
