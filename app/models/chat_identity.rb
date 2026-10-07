# frozen_string_literal: true

# A chat sender tied to the Aixle account that proved, through the messenger's
# own sign-in, that it is them (docs/design/teams-integration.md §9). It says who
# is asking; it never lets anyone sign in to Aixle.
class ChatIdentity < ApplicationRecord
  PROOFS = %w[microsoft_sign_in slack_sign_in].freeze

  belongs_to :user

  validates :provider, inclusion: { in: Chat::PROVIDERS.keys }
  validates :workspace_id, :external_user_id, :linked_at, presence: true
  validates :proof, inclusion: { in: PROOFS }

  def self.user_id_for(provider:, workspace_id:, external_user_id:)
    return nil if workspace_id.blank? || external_user_id.blank?

    where(provider: provider, workspace_id: workspace_id, external_user_id: external_user_id).pick(:user_id)
  end
end
