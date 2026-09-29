# frozen_string_literal: true

# A file that can be published at a stable anonymous link, served by
# Web::PublicAssetsController. One /share/:token route serves every kind, so a
# token is unique across all of them, not only within its own table.
#
# An including model provides `name`, `shared_file` and `shared_content_type`,
# and a `publicly_shared` scope.
module PubliclyShareable
  extend ActiveSupport::Concern

  MODELS = %w[Asset WorkflowRunAsset TaskAsset].freeze
  UNSHARED = { public_token: nil, shared_at: nil, shared_by_id: nil, shared_in_session_id: nil }.freeze

  included do
    belongs_to :shared_by, class_name: "User", optional: true
    belongs_to :shared_in_session, class_name: "TerminalSession", optional: true
  end

  class_methods do
    def generate_public_token
      loop do
        token = SecureRandom.urlsafe_base64(24)
        break token unless PubliclyShareable.token_taken?(token)
      end
    end
  end

  def self.find_shared(token)
    return if token.blank?

    MODELS.each do |name|
      shared = name.constantize.publicly_shared.find_by(public_token: token)
      return shared if shared
    end
    nil
  end

  def self.token_taken?(token)
    MODELS.any? { |name| name.constantize.exists?(public_token: token) }
  end

  # Idempotent: a shared file keeps its link. `by` and `session` record who
  # published it; an agent-made share names both.
  def share!(by: nil, session: nil)
    return public_token if shared?

    update!(share_attributes.merge(public_token: self.class.generate_public_token, shared_at: Time.current,
                                   shared_by: by || session&.user, shared_in_session: session))
    public_token
  end

  # The token goes with it: a later share is a new link, and the old one, wherever
  # it was pasted, stays dead.
  def unshare!
    update!(unshare_attributes)
  end

  def shared?
    public_token.present?
  end

  def share_url
    return nil unless shared?

    Rails.application.routes.url_helpers.public_asset_url(
      token: public_token, host: Settings.domain, protocol: Settings.protocol
    )
  end

  private

  def share_attributes = {}
  def unshare_attributes = UNSHARED
end
