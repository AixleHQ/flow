# frozen_string_literal: true

module Trackers
  # The port every tracker implements. One instance per connection; every issue
  # method takes the external scope it acts in and must refuse an issue that
  # lives outside it — an issue id alone is not proof of which project it is in.
  #
  # `ref` is whatever the caller has: an id, a readable key or a browser URL.
  # Values come back as Trackers::Issue / Comment / Status / Page, errors as
  # Trackers::Error.
  class Provider
    def self.for(integration)
      klass = Trackers.provider_class(integration.provider)
      raise Error.new("#{integration.provider} is not a task tracker", code: "unsupported") unless klass

      klass.new(integration)
    end

    attr_reader :integration

    def initialize(integration)
      @integration = integration
    end

    # Whether this connection may be mapped into `project` at all.
    def serves_project?(_project) = raise NotImplementedError

    # External scopes this connection can reach, for the "add tracker" picker.
    def scopes = raise NotImplementedError

    def covers_scope?(scope_id)
      scopes.any? { |scope| scope.id.to_s == scope_id.to_s }
    end

    # Identity of the external system an issue id is unique within — what an
    # ExternalResource link is keyed by.
    def instance = raise NotImplementedError

    # True when `ref` (a URL or key) unmistakably names an issue in `scope_id`.
    def owns_reference?(_scope_id, _ref) = false

    def describe(_scope_id) = raise NotImplementedError
    def get_issue(_scope_id, _ref) = raise NotImplementedError
    def search_issues(_scope_id, _filter, cursor: nil, limit: nil) = raise NotImplementedError
    def create_issue(_scope_id, _attributes) = raise NotImplementedError
    def update_issue(_scope_id, _ref, _attributes) = raise NotImplementedError
    def transition_issue(_scope_id, _ref, _status) = raise NotImplementedError
    def assign_issue(_scope_id, _ref, _assignee) = raise NotImplementedError
    def list_comments(_scope_id, _ref, cursor: nil, limit: nil) = raise NotImplementedError
    def add_comment(_scope_id, _ref, _body) = raise NotImplementedError
  end
end
