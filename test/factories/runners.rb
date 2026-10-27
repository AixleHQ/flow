# frozen_string_literal: true

FactoryBot.define do
  factory :runner do
    sequence(:name) { |n| "runner-#{n}" }
    company
    created_by { association(:user, company: company) }
    runner_type { :manual }
    max_concurrency { 1 }

    trait :manual do
      runner_type { :manual }
    end

    # Through a company-wide Coder integration, which any runner of the company may use.
    trait :coder do
      runner_type { :coder }
      integration { association(:integration, :coder, company: company) }
      config { { "template_id" => SecureRandom.uuid } }
    end

    trait :kubernetes do
      runner_type { :kubernetes }
      config { { "namespace" => "aixle-runners" } }
    end

    trait :project_runner do
      project { association(:project, company: company, owner: created_by) }
    end
  end
end
