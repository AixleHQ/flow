# frozen_string_literal: true

class RepositoryService
  def self.for(integration)
    case integration.provider.to_sym
    when :github then Github::RepositoryService.new(integration)
    when :gitlab then Gitlab::RepositoryService.new(integration)
    else raise "Unsupported provider: #{integration.provider}"
    end
  end
end
