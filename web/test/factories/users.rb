FactoryBot.define do
  factory :user do
    email
    name
    status { "active" }

    password { generate :password }
    password_confirmation { password }

    trait :admin do
      after(:create) do |user|
        user.add_role(:super_admin)
      end
    end

    trait :draft do
      status { "draft" }
    end

    trait :with_resource_role do
      transient do
        resource { }
        role { }
      end

      after(:create) do |user, evaluator|
        user.add_role(evaluator.role, evaluator.resource)
      end
    end

    trait :with_account do
      transient do
        account { }
      end

      after(:create) do |user, evaluator|
        user.account_users.create(account: evaluator.account, status: :active)
      end
    end
  end
end
