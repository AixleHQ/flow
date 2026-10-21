# frozen_string_literal: true

# The runtime value of one flag declared in config/feature_flags.yml, and the
# companies that are exceptions to it. Read through `Feature.enabled?`, never
# directly: FeatureFlags::Store turns these rows into the snapshot every check
# resolves against.
#
# A row is created the first time an admin touches the flag. It may outlive its
# declaration until it is pruned, so only creation requires a declared key.
class FeatureFlag < ApplicationRecord
  belongs_to :updated_by, class_name: "User", optional: true
  has_many :overrides, class_name: "FeatureFlagOverride", inverse_of: :feature_flag, dependent: :delete_all

  validates :key, presence: true, uniqueness: true
  validate :key_declared, on: :create

  # Two SELECTs, no matter how many flags or overrides there are.
  def self.load_snapshot
    flags = pluck(:id, :key, :enabled).to_h { |id, key, enabled| [ id, { key: key, global: enabled, overrides: {} } ] }
    FeatureFlagOverride.pluck(:feature_flag_id, :company_id, :enabled).each do |flag_id, company_id, enabled|
      flags[flag_id][:overrides][company_id] = enabled
    end

    FeatureFlags::Snapshot.new(flags.values.to_h { |flag| [ flag[:key], flag.slice(:global, :overrides) ] })
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
