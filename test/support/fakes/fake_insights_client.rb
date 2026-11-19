# frozen_string_literal: true

# The one fake of Insights::Client (docs/testing.md R3), contract-tested against the real
# client's shapes in test/services/insights/client_test.rb. Records every call; a test
# programs a failure with `fail_next(:method, Insights::Client::Error.new(...))`, and the
# export endpoint's answers with `export_results`.
class FakeInsightsClient
  attr_reader :calls, :exported
  attr_accessor :export_results, :organization_id, :organization_name, :projects_list

  def initialize(organization_id: "org-1", organization_name: "Acme")
    @calls = []
    @exported = []
    @failures = {}
    @export_results = []
    @organization_id = organization_id
    @organization_name = organization_name
    @projects_list = [ { "id" => "ip-1", "name" => "Platform" } ]
    @secrets = 0
  end

  def fail_next(method, error)
    @failures[method] = error
  end

  def claim(code:, company_id:, company_name:, deployment_id:, deployment_secret:)
    record(:claim, code: code, company_id: company_id, company_name: company_name, deployment_id: deployment_id,
                   deployment_secret: deployment_secret)
    { connection_id: "conn-#{company_id}", secret: next_secret, organization_id: organization_id,
      organization_name: organization_name }
  end

  def projects(secret)
    record(:projects, secret: secret)
    projects_list
  end

  def rotate(secret)
    record(:rotate, secret: secret)
    next_secret
  end

  def disconnect(secret)
    record(:disconnect, secret: secret)
    true
  end

  def export(secret, signal, payload)
    record(:export, secret: secret, signal: signal)
    @exported << payload
    export_results.shift || Insights::Client::ExportResult.new(status: 200, rejected: 0)
  end

  private

  def record(method, **args)
    @calls << [ method, args ]
    error = @failures.delete(method)
    raise error if error
  end

  def next_secret
    @secrets += 1
    "aixle_flow_secret_#{@secrets}"
  end
end
