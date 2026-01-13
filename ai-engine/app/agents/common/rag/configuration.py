from pydantic import Field

from agents.common.base.configuration import BaseAgentConfig, BaseLLMConfig


class RAGAgentConfig(BaseAgentConfig):
    llm: BaseLLMConfig = BaseLLMConfig(
        max_tokens=8000,
        temperature=0.1,
    )

    max_retrieval_attempts: int = Field(
        default=2,
        description="Maximum number of retrieval attempts with rewritten questions",
    )

    max_documents: int = Field(
        default=5, description="Maximum number of documents to retrieve"
    )

    score_threshold: float = Field(
        default=0.4, description="Minimum relevance score for retrieved documents"
    )

    enable_direct_answers: bool = Field(
        default=True, description="Whether to allow direct answers without retrieval"
    )

    context_window_size: int = Field(
        default=4000, description="Maximum context size for retrieved documents"
    )
