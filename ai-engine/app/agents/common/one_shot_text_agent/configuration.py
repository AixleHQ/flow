"""Configuration for OneShotTextAgent."""

from agents.common.base.configuration import BaseLLMConfig
from agents.common.base_openrouter_agent import BaseOpenRouterAgentConfig

class OneShotTextAgentConfig(BaseOpenRouterAgentConfig):
    """Configuration for one-shot text operations."""

    llm: BaseLLMConfig = BaseLLMConfig(
        temperature=0.1,
        max_tokens=4000,
    )
