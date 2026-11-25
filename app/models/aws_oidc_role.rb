# frozen_string_literal: true

# An IAM role a project's AWS OIDC integration can assume for a workflow step
# (docs/design/aws-oidc-integration.md §7.1). `name` is the profile name the step's
# container sees in ~/.aws/config.
class AwsOidcRole < ApplicationRecord
  NAME_FORMAT = /\A[a-z0-9][a-z0-9-]{0,62}\z/
  ARN_FORMAT = %r{\Aarn:aws[a-z-]*:iam::(\d{12}):role/[\w+=,.@/-]{1,512}\z}
  REGION_FORMAT = /\A[a-z]{2}(-[a-z]+)+-\d\z/
  DURATIONS = (900..3600)

  belongs_to :integration
  belongs_to :created_by, class_name: "User", optional: true

  validates :name, presence: true, format: { with: NAME_FORMAT, message: "use lowercase letters, digits and dashes" },
                   uniqueness: { scope: :integration_id }
  validates :role_arn, presence: true, format: { with: ARN_FORMAT, message: "must be an IAM role ARN" }
  validates :region, presence: true, format: { with: REGION_FORMAT, message: "must be an AWS region such as eu-west-1" }
  validates :session_duration_seconds, inclusion: { in: DURATIONS, message: "must be between 900 and 3600 seconds" }
  validate :integration_is_aws_oidc

  scope :for_project, lambda { |project|
    joins(:integration).where(integrations: { project_id: project.id, provider: "aws_oidc" })
  }

  def account_id
    role_arn.to_s[ARN_FORMAT, 1]
  end

  def project
    integration.project
  end

  private

  def integration_is_aws_oidc
    errors.add(:integration, "must be an AWS integration") unless integration&.aws_oidc?
  end
end
