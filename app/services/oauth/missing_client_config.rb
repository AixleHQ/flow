# frozen_string_literal: true

module Oauth
  # Raised by Oauth::Providers.client_for when a known provider has no configured
  # client_id (the provider stays inert until Settings carry credentials). Its own
  # file so it autoloads regardless of whether Oauth::Providers loaded first.
  class MissingClientConfig < StandardError; end
end
