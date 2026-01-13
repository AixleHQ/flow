"""Types for Temporal workflows - sandbox-safe.

IMPORTANT: This module must not import any external dependencies to avoid
breaking Temporal sandbox. Only use built-in Python types and typing module.
"""

from typing import TypedDict


class LLMModelsDict(TypedDict):
    domain_analysis_model: str
    feature_extraction_model: str
    user_story_model: str
    use_case_model: str
    diagram_model: str
    data_flow_model: str


class SpecificationContext(TypedDict):
    specification_id: int
    version_id: int
    models: LLMModelsDict
    workspace_id: int
    asset_ids: list[int]
