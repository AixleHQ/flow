# frozen_string_literal: true

class AgentCredential < ApplicationRecord
  extend Enumerize

  AGENT_TYPES = %w[codex cursor_cli open_code claude_code].freeze

  belongs_to :user

  enumerize :agent_type, in: AGENT_TYPES, predicates: true
  enumerize :status, in: %i[pending configured expired], default: :pending, predicates: true, scope: true

  validates :agent_type, presence: true, inclusion: { in: AGENT_TYPES }
  validates :agent_type, uniqueness: { scope: :user_id }

  encrypts :credentials_encrypted

  scope :configured, -> { with_status(:configured) }
  scope :pending, -> { with_status(:pending) }

  def mark_configured!(credentials)
    update!(
      credentials_encrypted: credentials.to_json,
      status: :configured,
      configured_at: Time.current
    )
  end

  def credentials
    return nil if credentials_encrypted.blank?

    JSON.parse(credentials_encrypted)
  rescue JSON::ParserError
    nil
  end

  def configured?
    status.to_sym == :configured && credentials_encrypted.present?
  end

  def display_name
    case agent_type
    when "codex" then "OpenAI Codex"
    when "cursor_cli" then "Cursor CLI"
    when "open_code" then "Open Code"
    when "claude_code" then "Claude Code"
    else agent_type.humanize
    end
  end

  def icon
    case agent_type
    when "codex" then "🤖"
    when "cursor_cli" then "▶️"
    when "open_code" then "💻"
    when "claude_code" then "🧠"
    else "⚡"
    end
  end
end
