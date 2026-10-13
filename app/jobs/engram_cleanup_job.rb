# frozen_string_literal: true

class EngramCleanupJob < ApplicationJob
  retry_on Engram::Client::Unavailable, wait: :polynomially_longer, attempts: 10

  def perform(engram_id, namespace)
    Engram::Client.build.delete(id: engram_id, project: namespace)
  end
end
