# frozen_string_literal: true

class NamespaceResourceQuota < ApplicationRecord
  # Polymorphic association - scope can be Project or User
  belongs_to :scope, polymorphic: true

  # Validations
  validates :scope_type, inclusion: { in: %w[Project User] }
  validates :scope_id, uniqueness: { scope: :scope_type }
  validates :max_pods, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :cpu_requests, format: { with: /\A\d+m?\z/, message: "must be a valid CPU quantity (e.g. '500m', '2')" }, allow_blank: true
  validates :cpu_limits, format: { with: /\A\d+m?\z/, message: "must be a valid CPU quantity (e.g. '500m', '2')" }, allow_blank: true
  validates :memory_requests, format: { with: /\A\d+(\.\d+)?(Ki|Mi|Gi|Ti|Pi|Ei|k|M|G|T|P|E)?\z/, message: "must be a valid memory quantity (e.g. '512Mi', '2Gi')" }, allow_blank: true
  validates :memory_limits, format: { with: /\A\d+(\.\d+)?(Ki|Mi|Gi|Ti|Pi|Ei|k|M|G|T|P|E)?\z/, message: "must be a valid memory quantity (e.g. '512Mi', '2Gi')" }, allow_blank: true

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[scope_type scope_id cpu_requests memory_requests cpu_limits memory_limits max_pods description created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end

  # Build the Kubernetes ResourceQuota hard limits hash from this record
  def to_k8s_hard_limits
    hard = {}
    hard["requests.cpu"] = cpu_requests if cpu_requests.present?
    hard["requests.memory"] = memory_requests if memory_requests.present?
    hard["limits.cpu"] = cpu_limits if cpu_limits.present?
    hard["limits.memory"] = memory_limits if memory_limits.present?
    hard["count/pods"] = max_pods.to_s if max_pods.present?
    hard
  end
end
