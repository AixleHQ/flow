# frozen_string_literal: true

namespace :coder do
  desc "Read-only: list what the pool rule of docs/design/session-integrations.md §4.1 and §4.2 would change " \
       "(workspaces that leave a pool, prefixes that break the rule). Run it on production before release."
  task audit_pools: :environment do
    Integration.where(provider: :coder, status: :active).order(:id).find_each do |integration|
      prefix = integration.coder_machine_prefix.to_s
      label = "integration #{integration.id} (#{integration.name})"

      puts "#{label}: no machine prefix (legacy), the pool is every workspace the token sees" if prefix.empty?
      if prefix.present? && !Coder::Pool.valid_prefix?(prefix)
        puts "#{label}: prefix #{prefix.inspect} breaks the rule (lowercase [0-9a-z-], no leading or trailing hyphen, " \
             "at most #{Coder::Pool::MAX_PREFIX_LENGTH} characters)"
      end
      puts "#{label}: no default template" if integration.coder_default_template.blank?
      next if prefix.empty?

      begin
        workspaces = Coder::WorkspaceService.new(integration).list(own: true)
      rescue Coder::WorkspaceService::OperationError, Coder::TokenService::AuthenticationError,
             Coder::TokenService::ConfigurationError => e
        puts "#{label}: workspaces could not be listed (#{e.class.name.demodulize})"
        next
      end

      workspaces.each do |workspace|
        name = workspace["name"].to_s
        next unless name.start_with?(prefix) && !Coder::Pool.matches?(prefix, name)

        puts "#{label}: workspace #{name.inspect} matches start_with?(#{prefix.inspect}) but not the pool pattern " \
             "and would leave the pool"
      end
    end
  end
end
