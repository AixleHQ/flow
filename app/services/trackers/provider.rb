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

    # Who this connection acts as in the tracker ({ "id", "name" }), once known.
    def identity
      integration.settings.to_h["tracker_identity"].presence
    end

    def own_actor?(actor)
      me = identity
      return false if me.blank? || actor.blank?

      (actor[:id].present? && actor[:id].to_s == me["id"].to_s) ||
        (actor[:name].present? && actor[:name].to_s.casecmp?(me["name"].to_s))
    end

    def mentions_self?(text)
      me = identity
      return false if me.blank? || text.blank?

      (me["id"].present? && text.include?(me["id"].to_s)) ||
        (me["name"].present? && text.downcase.include?("@#{me['name'].downcase}"))
    end

    # The status change a notification's hints describe, as event data
    # ({ "from" => {name, category}, "to" => {...} }), or nil when the status did
    # not change. The status is what the tracker's board shows; a provider whose
    # board columns differ from its workflow states decides here which one counts.
    def status_change(changes, issue)
      change = changes.find { |c| c[:field] == "status" }
      return unless change

      { "field" => "status", "from" => status_value(issue.scope_id, change[:from]),
        "to" => status_value(issue.scope_id, change[:to]) }.compact
    end

    def status_value(scope_id, name, category: nil)
      return if name.blank?

      { "name" => name, "category" => category || status_category(scope_id, name) }.compact
    end

    # Portable category of a status name, from describe(), cached briefly: every
    # event needs it and the process metadata rarely changes.
    def status_category(scope_id, name)
      return if name.blank?

      categories = Rails.cache.fetch([ "trackers", integration.id, scope_id.to_s, "status_categories" ], expires_in: 10.minutes) do
        describe(scope_id)[:statuses].to_h { |status| [ status.name.downcase, status.category ] }
      end
      categories[name.to_s.downcase]
    rescue Error
      nil
    end

    # The tracker account ids a notification carries, for TrackerAccount.
    def account_ids(_notification) = []

    # Deliveries through /webhooks/trackers (providers without a receiver of their own).
    def authentic_delivery?(_request, _raw_body, _subscription) = false
    def parse_delivery(_payload, _subscription) = []
    # The provider's own id for a delivery, when it has one, for deduplication.
    def delivery_id(_request, _payload) = nil

    # Make sure the tracker delivers the events tracker triggers wait for.
    # Best effort; a provider whose events arrive without a subscription does nothing.
    def ensure_event_delivery! = nil

    def describe(_scope_id) = raise NotImplementedError
    def get_issue(_scope_id, _ref) = raise NotImplementedError
    def search_issues(_scope_id, _filter, cursor: nil, limit: nil) = raise NotImplementedError
    def create_issue(_scope_id, _attributes) = raise NotImplementedError
    def update_issue(_scope_id, _ref, _attributes) = raise NotImplementedError
    def transition_issue(_scope_id, _ref, _status) = raise NotImplementedError
    def assign_issue(_scope_id, _ref, _assignee) = raise NotImplementedError
    def list_comments(_scope_id, _ref, cursor: nil, limit: nil) = raise NotImplementedError
    def add_comment(_scope_id, _ref, _body) = raise NotImplementedError

    # People an issue in the scope can be assigned to: [{ id:, name: }].
    def list_users(_scope_id, query:)
      raise Error.new("#{integration.provider} cannot list its users here; assign by the name the tracker shows",
                      code: "unsupported")
    end
  end
end
