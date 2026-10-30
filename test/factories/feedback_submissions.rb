# frozen_string_literal: true

FactoryBot.define do
  factory :feedback_submission do
    company
    user { association(:user, company: company) }
    kind { "bug" }
    message { "The board does not load after I archive a column." }
  end
end
