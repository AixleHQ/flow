# frozen_string_literal: true

# McpServer — MCP (Model Context Protocol) server configuration
#
# kind: internal | custom
# - internal: system-provided by Palad (e.g., palad-tools), no scope
# - custom: user-configured servers (Context7, Tavily, etc.) with Company/Project scope
#
# scope: Company | Project (polymorphic, null for internal)
class MCPServer < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[internal custom], default: :custom, predicates: true
  enumerize :transport, in: %i[http sse], default: :http

  # Polymorphic scope (Company or Project, null for internal)
  belongs_to :scope, polymorphic: true, optional: true

  # Auto-downcase and sanitize name
  def name=(val)
    super(val&.downcase&.gsub(/[^a-z0-9_-]/, "-"))
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_-]*\z/, message: "must start with letter, use lowercase letters, numbers, dashes, underscores" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :display_name, presence: true
  validates :kind, presence: true
  validates :url, presence: true, if: :custom?
  validates :scope, presence: true, if: :custom?

  # Scopes
  scope :internal_servers, -> { where(kind: "internal") }
  scope :custom_servers, -> { where(kind: "custom") }
  scope :for_company, ->(company) { custom_servers.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { custom_servers.where(scope_type: "Project", scope_id: project.id) }
  scope :enabled, -> { where(enabled: true) }

  # Get merged list of MCP servers for a project (internal + company + project)
  # Returns array with scope_indicator method on each server
  def self.merged_for_project(project)
    all_internal = internal_servers.enabled.to_a
    company_servers = for_company(project.company).enabled.to_a
    project_servers = for_project(project).enabled.to_a
    project_names = project_servers.map(&:name)

    result = []

    # Add internal servers (always included)
    all_internal.each do |server|
      server.define_singleton_method(:scope_indicator) { "internal" }
      result << server
    end

    # Add project servers (they override company servers)
    project_servers.each do |server|
      overrides = company_servers.any? { |cs| cs.name == server.name }
      server.define_singleton_method(:scope_indicator) { overrides ? "overrides_company" : "project" }
      result << server
    end

    # Add company servers that are NOT overridden by project
    company_servers.reject { |cs| project_names.include?(cs.name) }.each do |server|
      server.define_singleton_method(:scope_indicator) { "company" }
      result << server
    end

    result.sort_by(&:name)
  end

  # Get merged list for company level (internal + company)
  def self.merged_for_company(company)
    all_internal = internal_servers.enabled.to_a
    company_servers = for_company(company).enabled.to_a

    result = []

    all_internal.each do |server|
      server.define_singleton_method(:scope_indicator) { "internal" }
      result << server
    end

    company_servers.each do |server|
      server.define_singleton_method(:scope_indicator) { "company" }
      result << server
    end

    result.sort_by(&:name)
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name display_name kind scope_type enabled created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end
end
