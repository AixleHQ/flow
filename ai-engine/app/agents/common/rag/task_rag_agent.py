from typing import Any

from langchain_core.messages import HumanMessage
from langchain_openai import ChatOpenAI
from langgraph.graph.state import CompiledStateGraph
from core.logging import logger

from agents.common.base.configuration import BaseLLMConfig
from agents.common.base_langgraph_agent import BaseLangGraphAgent
from llm.llm_factory import LLMFactory
from models.llm import ModelDefinition
from models.telemetry import TelemetryContext

from .configuration import RAGAgentConfig
from .exceptions import NoDocumentsFoundError
from .models import TaskExecutionResponse, TaskRAGState
from .prompts import TASK_QUERY_GENERATION_HUMAN_PROMPT, TASK_QUERY_GENERATION_PROMPT
from .task_graph import build_task_rag_graph


class TaskRAGAgent(BaseLangGraphAgent[TaskExecutionResponse]):
    def __init__(
        self,
        telemetry: TelemetryContext,
        workspace_id: int,
        rag_model: ModelDefinition,
        config: RAGAgentConfig | None = None,
        asset_ids: list[int] | None = None,
        score_threshold: float | None = None,
    ) -> None:
        agent_config = config or RAGAgentConfig()
        agent_config.llm.model = rag_model
        if score_threshold is not None:
            agent_config.score_threshold = score_threshold
        super().__init__(
            agent_name="TaskRAGAgent",
            telemetry=telemetry,
            config=agent_config,
        )

        self.workspace_id = workspace_id
        self.rag_model = rag_model
        self.asset_ids = asset_ids
        self.graph = self.build_graph(rag_model, agent_config, workspace_id, asset_ids)

    def _create_llm_from_config(
        self, model: ModelDefinition, llm_config: BaseLLMConfig
    ) -> ChatOpenAI:
        return LLMFactory.create_langchain_openrouter_llm(
            model=model,
            temperature=llm_config.temperature,
            max_tokens=llm_config.max_tokens,
            reasoning_effort=llm_config.reasoning.effort,
        )

    def build_graph(
        self,
        rag_model: ModelDefinition,
        agent_config: RAGAgentConfig,
        workspace_id: int,
        asset_ids: list[int] | None = None,
    ) -> CompiledStateGraph[TaskRAGState, None, TaskRAGState, TaskRAGState]:
        llm = self._create_llm_from_config(
            model=rag_model, llm_config=agent_config.llm
        )
        return build_task_rag_graph(
            llm=llm,
            workspace_id=workspace_id,
            score_threshold=agent_config.score_threshold,
            asset_ids=asset_ids,
        )

    def invoke(
        self, state: TaskRAGState, metadata: dict[str, Any] | None = None
    ) -> dict:
        callback_handler = LLMFactory.create_langchain_callback_handler()

        config = self.build_langchain_config(
            callback_handler=callback_handler,
            metadata=metadata,
        )

        config["configurable"] = {
            "workspace_id": self.workspace_id,
            "model_name": self.rag_model,
            **config.get("configurable", {}),
        }

        return self.graph.invoke(state, config)  # type: ignore

    @staticmethod
    def _calculate_task_confidence(
        documents: list[str], rewrite_attempts: int, max_rewrite_attempts: int
    ) -> float:
        base_confidence = 0.5

        if documents:
            document_boost = min(len(documents) * 0.15, 0.4)
            base_confidence += document_boost

        attempt_penalty = (rewrite_attempts / max_rewrite_attempts) * 0.2
        base_confidence -= attempt_penalty

        return max(0.1, min(1.0, base_confidence))

    def execute_task(
        self,
        task_prompt: str,
        human_prompt: str,
        context_params: dict,
        max_rewrite_attempts: int = 2,
        structured_output_schema: type | None = None,
        search_query_prompt: str | None = None,
        search_query_human_prompt: str | None = None,
    ) -> TaskExecutionResponse | Any:
        logger.info("🚀 Starting task execution")

        formatted_human_prompt = (
            human_prompt.format(**context_params) if context_params else human_prompt
        )

        initial_state: TaskRAGState = {
            "messages": [HumanMessage(content="Starting task execution")],
            "task_prompt": task_prompt,
            "human_prompt": formatted_human_prompt,
            "search_query": "",
            "search_query_prompt": search_query_prompt or TASK_QUERY_GENERATION_PROMPT,
            "search_query_human_prompt": search_query_human_prompt
            or TASK_QUERY_GENERATION_HUMAN_PROMPT,
            "original_context": context_params,
            "generation": "",
            "documents": [],
            "grade": "",
            "steps": [],
            "rewrite_attempts": 0,
            "exit_without_documents": False,
        }

        metadata = {
            "model": self.rag_model,
            "workspace_id": self.workspace_id,
            "task": task_prompt,
            "context_params": context_params,
            "structured_output_schema": structured_output_schema,
        }

        final_state = self.invoke(initial_state, metadata=metadata)

        result = final_state.get("generation")
        if result == "No relevant documents found.":
            raise NoDocumentsFoundError(result)

        documents = final_state.get("documents", [])
        rewrite_attempts = final_state.get("rewrite_attempts", 0)
        confidence = self._calculate_task_confidence(
            documents, rewrite_attempts, max_rewrite_attempts
        )

        logger.info(
            f"✅ Task completed: {len(documents)} docs, calculated confidence {confidence:.2f}"
        )

        if hasattr(result, "model_dump_json") and callable(
            getattr(result, "model_dump_json", None)
        ):
            logger.info(
                f"🔧 Returning structured output: {structured_output_schema.__name__}"
            )

        return result
