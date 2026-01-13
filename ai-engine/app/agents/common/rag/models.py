from langchain_core.messages import BaseMessage
from pydantic import BaseModel
from typing_extensions import TypedDict

from agents.specification.feature_extraction_agent.feature_extraction import (
    FeatureExtractionResult,
)
from agents.specification.use_case_extraction_agent.use_case_extraction import (
    UseCaseExtractionResult,
)
from agents.specification.user_story_extraction_agent.user_story_extraction import (
    UserStoryExtractionResult,
)


class TaskRAGState(TypedDict):
    messages: list[BaseMessage]
    task_prompt: str
    human_prompt: str
    search_query: str
    search_query_prompt: str
    search_query_human_prompt: str
    original_context: dict
    generation: str | type[BaseModel]
    documents: list[str]
    grade: str
    steps: list[str]
    rewrite_attempts: int
    exit_without_documents: bool


type TaskExecutionResponse = (
    FeatureExtractionResult | UserStoryExtractionResult | UseCaseExtractionResult
)
