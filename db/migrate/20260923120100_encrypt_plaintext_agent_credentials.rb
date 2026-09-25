# frozen_string_literal: true

# Credentials stored before encryption hold plain JSON. They were read through a
# fallback that also let an undecryptable row pass for "no credential" and start
# a session without one; that fallback is gone, so they are encrypted here.
class EncryptPlaintextAgentCredentials < ActiveRecord::Migration[8.1]
  def up
    select_rows("SELECT id, encrypted_config_data FROM agent_credentials").each do |id, raw|
      next unless plaintext_json?(raw)

      credential = AgentCredential.find(id)
      credential.update_columns(encrypted_config_data: credential.send(:encrypt_secret, raw, column: "encrypted_config_data"))
    end
  end

  def down
    # Nothing to undo: the rows stay readable, only no longer as plaintext.
  end

  private

  def plaintext_json?(raw)
    JSON.parse(raw.to_s).is_a?(Hash)
  rescue JSON::ParserError
    false
  end
end
