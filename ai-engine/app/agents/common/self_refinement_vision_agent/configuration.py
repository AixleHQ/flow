"""Configuration for Self-Refinement Vision Agent."""

from pydantic import Field

from agents.common.base.configuration import BaseAgentConfig, BaseLLMConfig


class SelfRefinementVisionConfig(BaseAgentConfig):
    """Configuration for self-refinement vision operations."""

    vision_model: BaseLLMConfig = Field(default_factory=BaseLLMConfig)
    critic_model: BaseLLMConfig = Field(default_factory=BaseLLMConfig)
    summary_model: BaseLLMConfig = Field(default_factory=BaseLLMConfig)

    max_refinement_attempts: int = Field(
        default=2,
        description="Maximum refinement attempts for analysis",
    )
