# frozen_string_literal: true

module Integrations
  module UrlNormalizer
    def self.call(url) = url.to_s.strip.chomp("/")
  end

  class ConnectService
    def initialize(company:, connected_by:, project: nil)
      @company, @connected_by, @project = company, connected_by, project
    end

    def call(**params) = connect(params)

    private

    def connect(params)
      integration = @company.integrations.build(provider: provider, project: @project, connected_by: @connected_by,
        name: params[:name].presence || "#{provider.to_s.titleize} (unverified)", status: :error)
      integration.credentials_data = credentials(params)
      integration.settings = settings(params)
      begin
        verify!(integration)
        integration.status = :active
      rescue VerificationError => e
        integration.settings = integration.settings.merge("error" => e.message)
      end
      Integration.transaction do
        integration.save!
        after_connect!(integration, params) if integration.active?
      end
      integration
    end

    def provider = raise NotImplementedError
    def credentials(_params) = raise NotImplementedError
    def settings(_params) = raise NotImplementedError
    def verify!(_integration) = raise NotImplementedError
    def after_connect!(_integration, _params); end
  end
end
