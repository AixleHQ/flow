# frozen_string_literal: true

class Integration < ApplicationRecord
  extend Enumerize

  enumerize :provider, in: %i[github linear], predicates: true
  enumerize :status, in: %i[active inactive error], default: :inactive, predicates: true, scope: true

  belongs_to :company
  belongs_to :connected_by, class_name: "User"
  # has_many :repositories will be added in Story 14.2 when repositories table exists

  validates :name, presence: true
  validates :provider, presence: true

  scope :for_company, ->(company) { where(company: company) }
  scope :active, -> { where(status: "active") }

  def credentials_data=(hash)
    self.credentials = encryptor.encrypt_and_sign(hash.to_json)
  end

  def credentials_data
    return {} if credentials.blank?

    JSON.parse(encryptor.decrypt_and_verify(credentials))
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage,
         JSON::ParserError
    {}
  end

  def installation_id
    credentials_data["installation_id"]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name provider status created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[company connected_by]
  end

  private

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(encryption_key)
  end

  def encryption_key
    Settings.encryption.integrations_key.to_s.ljust(32, "0")[0..31]
  end
end
