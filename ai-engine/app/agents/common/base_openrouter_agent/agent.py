"""Base OpenRouter agent using instructor for structured outputs."""

from typing import Any

from core.logging import logger

from agents.common.base import BaseAgent
from agents.common.base.configuration import BaseLLMConfig
from config import settings
from llm.llm_factory import LLMFactory
from models.telemetry import TelemetryContext

from .configuration import BaseOpenRouterAgentConfig


class BaseOpenRouterAgent[T](BaseAgent[T]):
    """Base agent for OpenRouter with instructor support for structured outputs.

    Uses two clients:
    - Raw OpenAI client for plain text responses
    - Instructor-wrapped client for structured outputs (required by instructor library)
    """

    def __init__(
        self,
        agent_name: str,
        telemetry: TelemetryContext,
        config: BaseOpenRouterAgentConfig | None = None,
        structured_output_type: type[T] | None = None,
    ):
        super().__init__(agent_name, telemetry, structured_output_type, config)

        # Raw OpenAI client for text responses
        self.raw_client = LLMFactory.create_openrouter_llm()


        # Cache for instructor clients per model (different models need different modes)
        self._instructor_clients = {}

    def invoke_openrouter(
        self,
        llm: BaseLLMConfig,
        messages: list[dict[str, str]],
        metadata: dict[str, Any] | None = None,
        structured_output_schema: type | None = None,
        parallel_tool_calls: bool = False,
    ) -> Any:
        """Core LLM invocation.

        Uses instructor for structured outputs, raw OpenAI client for text.
        Validates model capabilities before making request.
        """
        model = llm.model
        model_name = model.identifier

        params = self._build_request_params(
            llm, messages, metadata, structured_output_schema, parallel_tool_calls
        )

        # Use appropriate client based on response type
        if structured_output_schema:
            # Get or create instructor client for this specific model
            # Different models need different instructor modes (TOOLS vs JSON)
            if model_name not in self._instructor_clients:
                self._instructor_clients[model_name] = (
                    LLMFactory.create_instructor_client(model)
                )
            client = self._instructor_clients[model_name]
        else:
            client = self.raw_client

        response = client.chat.completions.create(**params)

        self._log_response(response, llm, is_async=False)

        # Extract text content for non-structured responses
        if not structured_output_schema:
            return response.choices[0].message.content

        return response

    def _build_request_params(
        self,
        llm: BaseLLMConfig,
        messages: list[dict[str, str]],
        metadata: dict[str, Any] | None = None,
        response_model: type | None = None,
        parallel_tool_calls: bool = False,
    ) -> dict[str, Any]:
        """Build request parameters.

        For instructor (structured outputs): includes response_model
        For raw OpenAI (text): standard parameters only
        """
        model_name = llm.model.identifier

        enhanced_metadata = self.build_enhanced_metadata(
            model_name=model_name,
            metadata=metadata,
        )

        extra_body = {
            "usage": {"include": True},
            "max_tokens": llm.max_tokens,
        }

        # Add reasoning configuration if available
        if hasattr(llm, "reasoning") and llm.reasoning:
            reasoning_config = {}

            if llm.reasoning.effort:
                reasoning_config["effort"] = llm.reasoning.effort
            elif llm.reasoning.max_tokens is not None:
                reasoning_config["max_tokens"] = llm.reasoning.max_tokens

            if llm.reasoning.exclude is not None:
                reasoning_config["exclude"] = llm.reasoning.exclude

            if reasoning_config:
                extra_body["reasoning"] = reasoning_config

        params = {
            "model": model_name,
            "messages": messages,
            "temperature": llm.temperature,
            "extra_body": extra_body,
            "parallel_tool_calls": parallel_tool_calls,
        }

        # Add response_model ONLY for instructor client (structured outputs)
        if response_model is not None:
            params["response_model"] = response_model

        # Add Langfuse-specific parameters only if Langfuse is enabled
        if settings.langfuse.enabled:
            params["name"] = f"{self.agent_name}"
            params["metadata"] = enhanced_metadata

        return params

    def _log_response(
        self,
        response: Any,
        llm: BaseLLMConfig,
        is_async: bool = False,
    ) -> None:
        """Log instructor response."""
        model_name = llm.model.identifier
        async_suffix = " async" if is_async else ""
        logger.debug(
            f"Agent {self.agent_name} {model_name}{async_suffix} response: {response}"
        )
