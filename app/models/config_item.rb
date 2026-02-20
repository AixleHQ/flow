# frozen_string_literal: true

class ConfigItem < ApplicationRecord
  extend Enumerize

  # Enumerize for type (adds scopes: with_item_type(:secret), with_scope_type(:company))
  enumerize :item_type, in: %i[secret variable], default: :variable, predicates: true, scope: true

  # Polymorphic scope
  belongs_to :scope, polymorphic: true

  # Auto-upcase name
  def name=(val)
    super(val&.upcase)
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[A-Z][A-Z0-9_]*\z/, message: "must be uppercase with underscores (e.g., API_KEY)" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :item_type, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }
  validates :scope_id, presence: true

  # Value must be present on create
  validate :value_present_on_create, on: :create

  # Handle encryption before validation (after all attributes are set)
  before_validation :encrypt_value_if_secret

  # Scopes
  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

  # Get merged list of company + project items (for display)
  # Returns array with scope_indicator method on each item
  def self.merged_for_project(project)
    company_items = for_company(project.company)
    project_items = for_project(project)
    project_names = project_items.pluck(:name)

    result = []

    # Add project items first (they take precedence)
    project_items.each do |item|
      overrides = company_items.exists?(name: item.name)
      item.define_singleton_method(:scope_indicator) { overrides ? "overrides_company" : "project" }
      result << item
    end

    # Add company items that are NOT overridden
    company_items.where.not(name: project_names).each do |item|
      item.define_singleton_method(:scope_indicator) { "company" }
      result << item
    end

    result
  end

  # Get effective config items for container injection (resolved overrides)
  # Returns hash { name => decrypted_value }
  def self.effective_for_project(project)
    company_items = for_company(project.company).index_by(&:name)
    project_items = for_project(project).index_by(&:name)

    # Merge with project taking precedence
    company_items.merge(project_items).transform_values(&:decrypted_value)
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name description item_type scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end

  # Get display value (masked for secrets)
  def display_value
    secret? ? "••••••••" : value
  end

  # Check if value can be displayed
  def value_editable?
    variable?
  end

  # Store raw value temporarily - encryption happens in before_validation
  attr_accessor :raw_value

  # Intercept value assignment to handle secrets properly
  def value=(val)
    @raw_value = val
    super(val)
  end

  # Get decrypted value (for container injection only)
  def decrypted_value
    secret? ? decrypt(encrypted_value) : value
  end

  private

  def value_present_on_create
    if secret?
      errors.add(:value, "can't be blank") if encrypted_value.blank? && @raw_value.blank?
    elsif value.blank? && @raw_value.blank?
      errors.add(:value, "can't be blank")
    end
  end

  def encrypt_value_if_secret
    return unless @raw_value.present?

    if secret?
      self.encrypted_value = encrypt(@raw_value)
      self[:value] = nil
    else
      self.encrypted_value = nil
      self[:value] = @raw_value
    end
    @raw_value = nil # Clear temp value
  end

  def encrypt(plain_text)
    return nil if plain_text.blank?

    encryptor.encrypt_and_sign(plain_text)
  end

  def decrypt(cipher_text)
    return nil if cipher_text.blank?

    encryptor.decrypt_and_verify(cipher_text)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(encryption_key)
  end

  def encryption_key
    Settings.encryption.config_items_key.to_s.ljust(32, "0")[0..31]
  end
end
