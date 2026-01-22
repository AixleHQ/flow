FactoryBot.define do
  factory :user do
    email
    name
    password { generate :password }
    password_confirmation { password }

    trait :super_admin do
      role { "super_admin" }
      company { nil }
    end

    trait :with_company do
      association :company
    end

    trait :collaborator do
      role { "collaborator" }
      association :company
    end

    trait :admin_role do
      role { "admin" }
      association :company
    end
  end
end
