# frozen_string_literal: true

# The runtime value of one flag declared in config/feature_flags.yml, and the
# companies that are exceptions to it. Read through `Feature.enabled?`, never
# directly: FeatureFlags.snapshot turns these rows into the values every check
# resolves against.
#
# A row is created the first time an admin touches the flag. Rows of a key no
# longer declared are harmless: nothing reads them. Only creation requires a
# declared key.
class FeatureFlag < ApplicationRecord
  belongs_to :updated_by, class_name: "User", optional: true
  has_many :overrides, class_name: "FeatureFlagOverride", inverse_of: :feature_flag, dependent: :delete_all

  validates :key, presence: true, uniqueness: true
  validate :key_declared, on: :create

  # Every runtime value, frozen, in two SELECTs:
  # `{ key => { global: true | false | nil, overrides: { company_id => true | false } } }`.
  # A nil global means "use the declared default".
  def self.load_snapshot
    flags = pluck(:id, :key, :enabled).to_h { |id, key, enabled| [ id, [ key.to_sym, { global: enabled, overrides: {} } ] ] }
    FeatureFlagOverride.pluck(:feature_flag_id, :company_id, :enabled).each do |flag_id, company_id, enabled|
      flags.dig(flag_id, 1, :overrides)&.store(company_id, enabled)
    end

    flags.values.to_h { |key, values| [ key, values.merge(overrides: values[:overrides].freeze).freeze ] }.freeze
  end

  # nil once the flag is no longer declared.
  def definition
    FeatureFlags.registry.fetch(key) if FeatureFlags.registry.declared?(key)
  end

  private

  def key_declared
    return if key.blank? || FeatureFlags.registry.declared?(key)

    errors.add(:key, "is not declared in config/feature_flags.yml")
  end
end
