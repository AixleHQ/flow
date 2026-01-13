# PYTHON_PATH: app/

import factory
from factory import Factory, LazyAttribute, Sequence

from agents.specification.domain_analysis_agent.domain_extraction import Domain
from agents.specification.feature_extraction_agent import FeatureItem
from agents.specification.user_story_extraction_agent import UserStoryItem
from agents.specification.use_case_extraction_agent import UseCaseItem
from agents.specification.use_case_extraction_agent.use_case_extraction import (
    UseCaseData,
)
from services.specification.domain_generation.models import (
    FunctionalGroup,
    DomainCluster,
)


class DomainFactory(Factory):
    class Meta:
        model = Domain

    name = Sequence(lambda n: f"Domain {n}")
    description = LazyAttribute(lambda domain: f"Description for {domain.name}")
    justification = LazyAttribute(lambda domain: f"Justification for {domain.name}")


class FeatureItemFactory(Factory):
    class Meta:
        model = FeatureItem

    name = Sequence(lambda n: f"Feature {n}")
    description = LazyAttribute(
        lambda feature: f"Detailed description for {feature.name}"
    )
    justification = LazyAttribute(lambda feature: f"Justification for {feature.name}")
    technical_description = LazyAttribute(
        lambda feature: f"Technical implementation details for {feature.name}"
    )


class UserStoryItemFactory(Factory):
    class Meta:
        model = UserStoryItem

    name = Sequence(lambda n: f"User Story {n}")
    description = LazyAttribute(
        lambda user_story: f"As a user, I want {user_story.name.lower()}, so that I can achieve my goal"
    )
    justification = LazyAttribute(
        lambda user_story: f"Evidence-based justification for {user_story.name}"
    )
    technical_description = LazyAttribute(
        lambda user_story: f"Technical implementation details for {user_story.name}"
    )


class UseCaseDataFactory(Factory):
    class Meta:
        model = UseCaseData

    acceptance_criteria = LazyAttribute(
        lambda uc: [f"Acceptance criteria {i}" for i in range(1, 4)]
    )
    business_notes = LazyAttribute(
        lambda uc: [f"Business note {i}" for i in range(1, 3)]
    )
    success_metrics = LazyAttribute(
        lambda uc: [f"Success metric {i}" for i in range(1, 3)]
    )
    stakeholder_impact = LazyAttribute(
        lambda uc: [f"Stakeholder impact {i}" for i in range(1, 3)]
    )


class UseCaseItemFactory(Factory):
    class Meta:
        model = UseCaseItem

    name = Sequence(lambda n: f"Use Case {n}")
    description = LazyAttribute(
        lambda use_case: f"Detailed description for {use_case.name}"
    )
    data = factory.SubFactory(UseCaseDataFactory)
    justification = LazyAttribute(
        lambda use_case: f"Evidence-based justification for {use_case.name}"
    )
    gherkin_syntax = LazyAttribute(
        lambda use_case: f"Given {use_case.name.lower()}\nWhen action\nThen result"
    )


class FunctionalGroupFactory(Factory):
    class Meta:
        model = FunctionalGroup

    full_path = Sequence(lambda n: f"app/models/file_{n}.py")
    confidence = 0.8
    name = Sequence(lambda n: f"Functional Group {n}")
    business_domain_hint = LazyAttribute(lambda fg: f"Business domain for {fg.name}")
    entities = LazyAttribute(lambda fg: ["Entity1", "Entity2", "Entity3"])
    user_goal = LazyAttribute(lambda fg: f"User goal for {fg.name}")
    operations = LazyAttribute(lambda fg: ["operation1", "operation2"])
    business_rules = LazyAttribute(lambda fg: ["Rule 1", "Rule 2"])


class DomainClusterFactory(Factory):
    class Meta:
        model = DomainCluster

    cluster_id = Sequence(lambda n: n)
    groups = factory.LazyFunction(lambda: [FunctionalGroupFactory()])
    avg_confidence = 0.8
    status = "main"
