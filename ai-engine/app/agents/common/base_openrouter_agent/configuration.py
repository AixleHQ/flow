"""Configuration for BaseOpenRouterAgent."""

from agents.common.base.configuration import BaseAgentConfig, BaseLLMConfig


class BaseOpenRouterAgentConfig(BaseAgentConfig):
    """Base configuration for OpenRouter agents."""

    llm: BaseLLMConfig = BaseLLMConfig()
