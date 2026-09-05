# frozen_string_literal: true

# Converts the old homogeneous per-Pod quota into concurrent-session capacity.
# Explicit scope overrides are imported; deployment defaults are reported too.
class SessionQuotaMigration
  def self.plan
    defaults = %w[Project User].to_h { |type| [ type, capacity(type, nil) ] }
    { defaults: defaults, overrides: NamespaceResourceQuota.order(:id).map do |quota|
      { scope_type: quota.scope_type, scope_id: quota.scope_id, max_sessions: capacity(quota.scope_type, quota) }
    end }
  end

  def self.capacity(type, quota)
    defaults = Settings.namespace_resource_quotas.public_send("#{type.downcase}_defaults")
    limits = []
    %i[cpu_requests memory_requests cpu_limits memory_limits max_pods].each do |field|
      value = quota&.public_send(field).presence || defaults.public_send(field)
      next if value.blank?
      if field == :max_pods
        limits << Integer(value)
      else
        resource, direction = field.to_s.split("_")
        per_pod = Settings.kubernetes.public_send("runtime_#{direction}_#{resource}")
        denominator = quantity(per_pod, cpu: resource == "cpu")
        raise "Per-Pod #{field} must be positive" unless denominator.positive?
        limits << (quantity(value, cpu: resource == "cpu") / denominator).floor
      end
    end
    result = limits.min
    raise "No positive session capacity for #{type}; operator decision required" unless result&.positive?
    result
  end

  def self.quantity(value, cpu:)
    raw = value.to_s
    return Rational(raw.delete_suffix("m")) / 1000 if cpu && raw.end_with?("m")
    return Rational(raw) if cpu
    match = /\A(\d+(?:\.\d+)?)(Ki|Mi|Gi|Ti|Pi|Ei|k|M|G|T|P|E)?\z/.match(raw)
    raise ArgumentError, "Unsupported memory quantity: #{raw}" unless match
    unit = match[2]
    power = unit ? %w[k M G T P E].index(unit.delete_suffix("i").sub("K", "k")) + 1 : 0
    Rational(match[1]) * (unit&.end_with?("i") ? 1024 : 1000)**power
  end
end
