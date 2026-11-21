# frozen_string_literal: true

namespace :agents do
  desc "Print every model × reasoning-effort launch a member is offered for a runtime, one JSON " \
       "object per line, for bin/agent-effort-probe. Args: email, agent_type, company_id (optional " \
       "when the user belongs to one company), plain (1 adds each model's launch without a level)."
  task :effort_plan, %i[email agent_type company_id plain] => :environment do |_task, args|
    memberships = User.find_by!(email: args.fetch(:email)).company_memberships
    membership = args[:company_id].present? ? memberships.find_by!(company_id: args[:company_id]) : memberships.sole

    plan = Agents::EffortProbePlan.for(membership, args.fetch(:agent_type), plain: args[:plain] == "1")
    plan.each { |row| puts row.to_json }
  end
end
