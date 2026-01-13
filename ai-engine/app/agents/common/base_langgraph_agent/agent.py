"""Base LangGraph agent implementation."""

from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from agents.common.base import BaseAgent
from agents.common.base.configuration import BaseLLMConfig
from llm.llm_factory import LLMFactory
from models.telemetry import TelemetryContext
from models.llm import ModelDefinition


class BaseLangGraphAgent[T](BaseAgent[T]):
    """Base agent for LangGraph-based workflows."""

    def __init__(
        self,
        agent_name: str,
        telemetry: TelemetryContext,
        config,
    ):
        super().__init__(agent_name, telemetry, None, config)

    def _create_llm_from_config(
        self, model: ModelDefinition, llm_config: BaseLLMConfig
    ) -> ChatOpenAI:
        """Create LangChain LLM from configuration."""
        return LLMFactory.create_langchain_openrouter_llm(
            model=model,
            temperature=llm_config.temperature,
            max_tokens=llm_config.max_tokens,
        )

    def _invoke_langchain_llm(
        self,
        llm: ChatOpenAI,
        system_prompt: str,
        user_prompt: str,
        structured_output_schema: Any,
        metadata: dict[str, Any] | None = None,
    ) -> Any:
        """Invoke LangChain LLM with telemetry and structured output."""
        callback_handler = LLMFactory.create_langchain_callback_handler()
        config = self.build_langchain_config(
            callback_handler=callback_handler,
            metadata=metadata,
        )

        structured_llm = llm.with_structured_output(
            structured_output_schema, method="json_schema"
        )

        messages = [
            SystemMessage(content=system_prompt),
            HumanMessage(content=user_prompt),
        ]

        response = structured_llm.invoke(messages, config=config)
        return response

    def invoke(self, state: dict, metadata: dict[str, Any] | None = None) -> dict:
        """Invoke the LangGraph workflow."""
        callback_handler = LLMFactory.create_langchain_callback_handler()

        config = self.build_langchain_config(
            callback_handler=callback_handler,
            metadata=metadata,
        )

        return self.graph.invoke(state, config)
