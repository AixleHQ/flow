"""Base configuration for all agents."""

from typing import Literal

from pydantic import BaseModel, Field

from models.llm import ModelDefinition


class BaseReasoningConfig(BaseModel):
    """Base reasoning configuration for LLM models."""

    effort: Literal["high", "medium", "low"] = Field(
        default="low", description="OpenAI-style reasoning effort setting"
    )
    max_tokens: int | None = Field(
        default=None, description="Non-OpenAI-style reasoning effort setting"
    )
    exclude: bool = Field(
        default=True, description="Whether to exclude reasoning from the response"
    )


class BaseLLMConfig(BaseModel):
    """Base LLM configuration for agents."""

    model: ModelDefinition | None = Field(
        default=None, description="LLM model definition"
    )
    temperature: float = Field(default=0.1, description="LLM temperature")
    max_tokens: int = Field(default=4000, description="LLM max tokens")
    seed: int = Field(default=42, description="LLM seed")
    reasoning: BaseReasoningConfig = Field(
        default_factory=BaseReasoningConfig, description="LLM reasoning configuration"
    )


class BaseEmbeddingConfig(BaseModel):
    """Base embedding configuration for agents."""

    model_name: str = Field(
        default="text-embedding-3-small", description="Embedding model name"
    )


class BaseAgentConfig(BaseModel):
    """Base configuration for all agents."""

    llm: BaseLLMConfig | None = None
    embedding: BaseEmbeddingConfig = Field(default_factory=BaseEmbeddingConfig)
