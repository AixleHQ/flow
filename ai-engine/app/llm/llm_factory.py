"""Clean LLM client factory following telemetry_demo pattern."""

from typing import Any, Literal

import instructor
from langchain_openai import ChatOpenAI
from core.logging import logger

from config import settings
from utils import CostTrackingCallbackHandler
from models.llm import ModelDefinition


class LLMFactory:
    """Creates LLM clients with clean configuration."""

    @staticmethod
    def create_langchain_openrouter_llm(
        model: ModelDefinition,
        temperature: float = 0.1,
        max_tokens: int | None = None,
        reasoning_effort: Literal["high", "medium", "low"] | None = None,
    ) -> ChatOpenAI:
        """Create LangChain ChatOpenAI client configured for OpenRouter."""
        if not settings.openrouter.api_key:
            raise ValueError("Missing OPENROUTER_API_KEY in configuration")

        model_name = model.identifier

        model_kwargs: dict[str, Any] = {}
        if reasoning_effort:
            model_kwargs["reasoning_effort"] = reasoning_effort

        return ChatOpenAI(
            model=model_name,
            api_key=settings.openrouter.api_key,
            base_url=settings.openrouter.base_url,
            temperature=temperature,
            model_kwargs=model_kwargs,
            extra_body={
                "usage": {"include": True},
                "max_tokens": max_tokens,
            },
            timeout=300,
            max_retries=settings.openrouter.max_retries,
        )

    @staticmethod
    def create_openrouter_llm():
        """Create direct OpenAI client configured for OpenRouter with Langfuse integration."""
        if not settings.openrouter.api_key:
            raise ValueError("Missing OPENROUTER_API_KEY in configuration")

        # Import OpenAI client with Langfuse integration for telemetry
        if settings.langfuse.enabled:
            try:
                from langfuse.openai import OpenAI

                logger.info("Using Langfuse-integrated OpenAI client for telemetry")
            except ImportError:
                from openai import OpenAI

                logger.warning(
                    "Langfuse OpenAI integration not available, using standard OpenAI client"
                )
        else:
            from openai import OpenAI

        return OpenAI(
            api_key=settings.openrouter.api_key,
            base_url=settings.openrouter.base_url,
            max_retries=settings.openrouter.max_retries,
        )

    @staticmethod
    def create_instructor_client(
        model: ModelDefinition | None = None,
    ) -> instructor.Instructor:
        """Create instructor-wrapped OpenAI client for structured outputs.

        Automatically selects appropriate mode based on model capabilities.
        Wraps Langfuse-integrated client to maintain telemetry.

        Args:
            model: Optional model object to determine instructor mode
        """
        base_client = LLMFactory.create_openrouter_llm()
        mode = getattr(instructor.Mode, model.instructor_mode)

        return instructor.from_openai(base_client, mode=mode)

    @staticmethod
    def create_langchain_callback_handler() -> CostTrackingCallbackHandler | None:
        """Create LangChain cost tracking callback handler if Langfuse is enabled."""
        if not settings.langfuse.enabled:
            return None

        if not settings.langfuse.public_key or not settings.langfuse.secret_key:
            logger.warning("Langfuse enabled but keys not configured")
            return None

        try:
            return CostTrackingCallbackHandler()
        except Exception as e:
            logger.error(f"Failed to create callback handler: {e}")
            return None
