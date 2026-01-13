"""Configuration for BatchTextAgent."""

from agents.common.base.configuration import BaseLLMConfig
from agents.common.base_openrouter_agent import BaseOpenRouterAgentConfig


class BatchTextAgentConfig(BaseOpenRouterAgentConfig):
    """Configuration for batch text processing operations."""

    llm: BaseLLMConfig = BaseLLMConfig(
        temperature=0.1,
        max_tokens=4000,
    )

    # Chunking configuration
    max_chunk_size: int = 15000
    """Maximum size of each content chunk in characters."""

    # Batch processing configuration
    max_concurrent_chunks: int = 5
    """Maximum number of chunks to process concurrently."""
