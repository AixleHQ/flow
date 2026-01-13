from typing import Any
from temporalio import activity

from services.specification import (
    DomainGenerationService,
    FeatureGenerationService,
    UserStoryGenerationService,
    UseCaseGenerationService,
    ErdDiagramService,
    DataflowDiagramService,
)
from services.payload_service import PayloadService
from models.activity_types.specification import (
    SpecificationContextData,
    DomainContext,
    FeatureContext,
    UserStoryContext,
    DomainsActivityInput,
    FeaturesActivityInput,
    UserStoriesActivityInput,
    UseCasesActivityInput,
    ErdDiagramActivityInput,
    DataflowDiagramActivityInput,
    DiagramContext,
)


@activity.defn(name="generate_domains")
def generate_domains(data: dict[str, Any]) -> str:
    activity_input = DomainsActivityInput(**data)
    context = PayloadService.load_object(
        activity_input.domain_context_payload_key, model=SpecificationContextData
    )

    generated_domains = DomainGenerationService.generate_domains(
        domain_analysis_model=activity_input.domain_analysis_model,
        context=context,
    )

    domains_list = [d.model_dump() for d in generated_domains]
    return PayloadService.store_json(
        domains_list, f"domains_version_{context.version_id}"
    )


@activity.defn(name="generate_features")
def generate_features(data: dict[str, Any]) -> str | None:
    activity_input = FeaturesActivityInput(**data)
    domain_context = PayloadService.load_object(
        activity_input.domain_context_payload_key, model=DomainContext
    )

    generated_features = FeatureGenerationService.generate_features(
        feature_extraction_model=activity_input.feature_extraction_model,
        context=domain_context,
    )

    if not generated_features:
        return None

    features_list = [f.model_dump() for f in generated_features]
    return PayloadService.store_json(
        {"domain_id": domain_context.domain_id, "features": features_list},
        f"features_version_{domain_context.version_id}_domain_{domain_context.domain_id}",
    )


@activity.defn(name="generate_user_stories")
def generate_user_stories(data: dict[str, Any]) -> str | None:
    activity_input = UserStoriesActivityInput(**data)
    context = PayloadService.load_object(
        activity_input.feature_context_payload_key, model=FeatureContext
    )

    user_stories = UserStoryGenerationService.generate_user_stories(
        user_story_extraction_model=activity_input.user_story_extraction_model,
        context=context,
    )

    if not user_stories:
        return None

    user_stories_list = [us.model_dump() for us in user_stories]
    return PayloadService.store_json(
        {"feature_id": context.feature_id, "user_stories": user_stories_list},
        f"user_stories_version_{context.version_id}_feature_{context.feature_id}",
    )


@activity.defn(name="generate_use_cases")
def generate_use_cases(data: dict[str, Any]) -> str | None:
    activity_input = UseCasesActivityInput(**data)
    context = PayloadService.load_object(
        activity_input.user_story_context_payload_key, model=UserStoryContext
    )

    use_cases = UseCaseGenerationService.generate_use_cases(
        use_case_extraction_model=activity_input.use_case_extraction_model,
        context=context,
    )

    if not use_cases:
        return None

    use_cases_list = [uc.model_dump() for uc in use_cases]
    return PayloadService.store_json(
        {"user_story_id": context.user_story_id, "use_cases": use_cases_list},
        f"use_cases_version_{context.version_id}_story_{context.user_story_id}",
    )


@activity.defn(name="generate_erd_diagram")
def generate_erd_diagram(data: dict[str, Any]) -> str | None:
    activity_input = ErdDiagramActivityInput(**data)
    diagram_context = PayloadService.load_object(
        activity_input.diagram_context_payload_key, model=DiagramContext
    )

    erd_diagram = ErdDiagramService.generate_erd_diagram(
        erd_model=activity_input.erd_model,
        context=diagram_context,
    )

    if not erd_diagram:
        return None

    return PayloadService.store_json(
        {"diagram_content": erd_diagram, "diagram_type": "erd"},
        f"erd_diagram_version_{diagram_context.version_id}",
    )


@activity.defn(name="generate_dataflow_diagram")
def generate_dataflow_diagram(data: dict[str, Any]) -> str | None:
    activity_input = DataflowDiagramActivityInput(**data)
    diagram_context = PayloadService.load_object(
        activity_input.diagram_context_payload_key, model=DiagramContext
    )

    dataflow_diagram = DataflowDiagramService.generate_dataflow_diagram(
        dataflow_model=activity_input.dataflow_model,
        context=diagram_context,
    )

    if not dataflow_diagram:
        return None

    return PayloadService.store_json(
        {"diagram_content": dataflow_diagram, "diagram_type": "data_flow"},
        f"dataflow_diagram_version_{diagram_context.version_id}",
    )
