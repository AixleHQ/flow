"""Configuration for MixtureOfExpertsAgent."""

from agents.common.base.configuration import BaseLLMConfig
from agents.common.base_openrouter_agent import BaseOpenRouterAgentConfig


class MixtureOfExpertsAgentConfig(BaseOpenRouterAgentConfig):
    """Base configuration for MOE (Mixture of Experts) agents using 3-consensus scheme."""

    expert1_llm: BaseLLMConfig = BaseLLMConfig(
        temperature=0.1,
        max_tokens=8000,
    )

    expert2_llm: BaseLLMConfig = BaseLLMConfig(
        temperature=0.1,
        max_tokens=8000,
    )

    expert3_llm: BaseLLMConfig = BaseLLMConfig(
        temperature=0.1,
        max_tokens=8000,
    )

    judge_llm: BaseLLMConfig = BaseLLMConfig(
        temperature=0.1,
        max_tokens=8000,
    )
