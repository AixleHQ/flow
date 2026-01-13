import factory
from factory import LazyAttribute, Sequence, DictFactory


class CodebaseFileDataFactory(DictFactory):
    file_path = Sequence(lambda n: f"app/models/file_{n}.py")
    category = LazyAttribute(
        lambda file_data: [
            {
                "name": f"Category {getattr(file_data, 'file_path', 'file')}",
                "confidence": 0.9,
            }
        ]
    )
    business_logic_factor = 0.8
    functional_group_candidates = LazyAttribute(
        lambda file_data: [
            {
                "name": f"Group for {getattr(file_data, 'file_path', 'file')}",
                "confidence": 0.9,
                "business_domain_hint": "Business domain hint",
                "entities": ["Entity1", "Entity2"],
                "user_goal": "User goal description",
                "operations": ["operation1", "operation2"],
                "business_rules": ["Rule 1", "Rule 2"],
            }
        ]
    )


class SpecificationContextDataFactory(DictFactory):
    version_id = Sequence(lambda n: n + 1)
    workspace_id = Sequence(lambda n: n + 1)
    asset_ids = [1, 2]
    codebase_files_data = factory.LazyFunction(
        lambda: [
            CodebaseFileDataFactory(
                file_path="app/models/user.py",
                category=[{"name": "User Management", "confidence": 0.9}],
                functional_group_candidates=[
                    {
                        "name": "Authentication",
                        "confidence": 0.9,
                        "business_domain_hint": "User authentication and management",
                        "entities": ["User", "Session", "Token"],
                        "user_goal": "Authenticate users and manage sessions",
                        "operations": ["login", "logout", "refresh_token"],
                        "business_rules": [
                            "Password must be hashed",
                            "Session expires after 30 minutes",
                        ],
                    }
                ],
            ),
            CodebaseFileDataFactory(
                file_path="app/services/payment.py",
                category=[{"name": "Payment Processing", "confidence": 0.95}],
                business_logic_factor=0.9,
                functional_group_candidates=[
                    {
                        "name": "Billing",
                        "confidence": 0.9,
                        "business_domain_hint": "Payment processing and billing",
                        "entities": ["Payment", "Invoice", "Transaction"],
                        "user_goal": "Process payments and generate invoices",
                        "operations": ["process_payment", "refund", "generate_invoice"],
                        "business_rules": [
                            "Payment must be verified",
                            "Refunds processed within 7 days",
                        ],
                    }
                ],
            ),
        ]
    )
    non_code_asset_ids = [3, 4]


class DomainContextFactory(DictFactory):
    version_id = Sequence(lambda n: n + 1)
    workspace_id = Sequence(lambda n: n + 1)
    asset_ids = [1, 2, 3]
    domain_id = Sequence(lambda n: n + 1)
    domain_name = Sequence(lambda n: f"Domain {n}")
    domain_description = LazyAttribute(
        lambda context: f"Description for {getattr(context, 'domain_name', 'Domain')}"
    )
    domain_justification = LazyAttribute(
        lambda context: f"Justification for {getattr(context, 'domain_name', 'Domain')}"
    )


class FeatureContextFactory(DictFactory):
    version_id = Sequence(lambda n: n + 1)
    workspace_id = Sequence(lambda n: n + 1)
    asset_ids = [1, 2, 3]
    feature_id = Sequence(lambda n: n + 1)
    feature_name = Sequence(lambda n: f"Feature {n}")
    feature_description = LazyAttribute(
        lambda context: f"Detailed description for {getattr(context, 'feature_name', 'Feature')}"
    )
    feature_technical_description = LazyAttribute(
        lambda context: f"Technical implementation for {getattr(context, 'feature_name', 'Feature')}"
    )
    domain_name = Sequence(lambda n: f"Domain {n}")
    domain_description = LazyAttribute(
        lambda context: f"Description for {getattr(context, 'domain_name', 'Domain')}"
    )


class UserStoryContextFactory(DictFactory):
    version_id = Sequence(lambda n: n + 1)
    workspace_id = Sequence(lambda n: n + 1)
    asset_ids = [1, 2, 3]
    user_story_id = Sequence(lambda n: n + 1)
    user_story_name = Sequence(lambda n: f"User Story {n}")
    user_story_description = LazyAttribute(
        lambda context: f"As a user, I want {getattr(context, 'user_story_name', 'User Story')}, so that I can achieve my goal"
    )
    user_story_technical_description = LazyAttribute(
        lambda context: f"Technical implementation for {getattr(context, 'user_story_name', 'User Story')}"
    )
    domain_name = Sequence(lambda n: f"Domain {n}")
