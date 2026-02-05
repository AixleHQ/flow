# API Controller Patterns (2026-01-29)

## Minimalist Controller Style

Controllers should be as simple as possible. We use `respond_with` and built-in Rails patterns.

**Controller example:**
```ruby
# app/controllers/api/v1/company/users_controller.rb
module Api::V1::Company
  class UsersController < ApplicationController
    # GET /api/v1/company/users
    def index
      users = current_company.users.ransack(params[:q]).result
      respond_with paginate(users)
    end

    # POST /api/v1/company/users
    def create
      user = current_company.users.create(user_params)
      respond_with user
    end

    # PATCH /api/v1/company/users/:id
    def update
      user = current_company.users.find(params[:id])
      user.update(user_params)
      respond_with user
    end

    private

    def user_params
      params.require(:user).permit(:email, :name, :role, :state_event)
    end
  end
end
```

## Namespace Base Controllers

For namespaces we create a base controller with shared logic:

```ruby
# app/controllers/api/v1/company/application_controller.rb
module Api::V1::Company
  class ApplicationController < Api::V1::ApplicationController
    before_action :dynamic_authorize!

    def current_company
      @current_company ||= current_user.company
    end
  end
end
```

## Dynamic Authorization (AuthorizationConcern)

Authorization is performed automatically via `dynamic_authorize!` in the namespace's base controller.

**How it works:**

1. `AuthorizationConcern` defines `dynamic_authorize!` which:
   - Finds the policy by the controller name: `Api::V1::Company::UsersController` → `Api::V1::Company::UsersPolicy`
   - Calls `authorize(policy_record, policy_class: policy_class)`
   - `policy_record` — a method that is overridden in the controller

2. **Policy naming convention:**
   - Controller: `app/controllers/api/v1/company/users_controller.rb`
   - Policy: `app/policies/api/v1/company/users_policy.rb`

```ruby

```

4. **Policy structure:**
```ruby
# app/policies/api/v1/company/users_policy.rb
module Api::V1::Company
  class UsersPolicy < ApplicationPolicy
    def index?
      current_user.admin?
    end

    def create?
      current_user.admin?
    end

    def update?
      current_user.admin? && same_company?
    end

    def destroy?
      current_user.admin? && same_company? && not_self?
    end

    private

    def current_user
      context.respond_to?(:user) ? context.user : context
    end

    def same_company?
      record.company_id == current_user.company_id
    end

    def not_self?
      record.id != current_user.id
    end
  end
end
```

## Key Principles

1. **Minimum code** — 2-3 lines per action at most
2. **respond_with** — automatically selects the response format and status
3. **Ransack** — for filtering: `Model.ransack(params[:q]).result`
4. **paginate** — for pagination (Kaminari or Pagy)
5. **Namespace base controllers** — shared logic (current_company) + `before_action :dynamic_authorize!`
6. **Dynamic authorization** — policies are matched automatically by controller name
7. **policy_record** — overridden in the controller to return a record or a class
8. **Memoization** — `@variable ||=` for caching within a request
9. **No before_action for set_resource** — we fetch the record directly in the action for explicitness
