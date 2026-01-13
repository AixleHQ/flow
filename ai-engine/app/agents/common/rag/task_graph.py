from typing import Final, Literal

from langchain_core.messages import (
    AIMessage,
    BaseMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
)
from langchain_core.runnables import RunnableConfig
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph
from langgraph.graph.state import CompiledStateGraph
from langgraph.prebuilt import ToolNode
from core.logging import logger

from .models import TaskRAGState
from .prompts import (
    QUERY_IMPROVEMENT_HUMAN_PROMPT,
    QUERY_IMPROVEMENT_PROMPT,
    TASK_DOCUMENT_GRADING_HUMAN_PROMPT,
    TASK_DOCUMENT_GRADING_PROMPT,
    TASK_EXECUTION_HUMAN_PROMPT,
)
from .tools import create_dynamic_retriever_tool

MAX_REWRITE_ATTEMPTS: Final[int] = 2
NO_DOCUMENTS_FOUND: Final[str] = "No relevant documents found."


class TaskRAGGraph:
    def __init__(
        self,
        llm: ChatOpenAI,
        workspace_id: int,
        score_threshold: float,
        asset_ids: list[int] | None = None,
    ):
        self.llm = llm
        self.workspace_id = workspace_id
        self.asset_ids = asset_ids
        self.score_threshold = score_threshold

    @staticmethod
    def _append_step(state: TaskRAGState, step_name: str) -> list[str]:
        existing_steps = state.get("steps", [])
        steps = [str(step) for step in existing_steps] if existing_steps else []
        steps.append(step_name)
        return steps

    @staticmethod
    def _get_documents_from_messages(
        messages: list[BaseMessage],
    ) -> list[str | list[str | dict]]:
        documents = []
        for message in messages:
            if not isinstance(message, ToolMessage):
                continue

            message_content_exists = (
                message.content and message.content != NO_DOCUMENTS_FOUND
            )
            if message_content_exists:
                documents.append(message.content)
        return documents

    def _generate_search_query(
        self, state: TaskRAGState, config: RunnableConfig
    ) -> TaskRAGState:
        original_context = state["original_context"]
        domain_name = original_context.get("domain_name", "Unknown Task")
        logger.info(f"🔍 Generating search query for domain_name: {domain_name}")

        query_prompt = state["search_query_human_prompt"]
        messages_for_llm = [
            SystemMessage(content=state["search_query_prompt"]),
            HumanMessage(content=query_prompt),
        ]

        response = self.llm.invoke(messages_for_llm)
        search_query = (
            response.content.strip()
            if isinstance(response.content, str) and response.content
            else "search query"
        )
        logger.info(f"🎯 Search query: {search_query}")

        tool_call = {
            "name": "retrieve related docs",
            "args": {"query": search_query},
            "id": "call_1",
        }
        ai_message = AIMessage(
            content="Searching for relevant documents", tool_calls=[tool_call]
        )
        steps = self._append_step(state, "generate_search_query")

        return state | {
            "messages": [ai_message],
            "search_query": search_query,
            "generation": "",
            "documents": [],
            "grade": "",
            "steps": steps,
        }

    def _check_documents_found(
        self, state: TaskRAGState
    ) -> Literal[
        "grade_documents_for_task", "improve_search_query", "exit_without_documents"
    ]:
        rewrite_attempts = state.get("rewrite_attempts", 0)

        messages = state.get("messages", [])
        documents = self._get_documents_from_messages(messages)

        if not documents:
            if rewrite_attempts >= MAX_REWRITE_ATTEMPTS:
                logger.warning(
                    "🚨 Max rewrite attempts reached, no relevant documents found - exiting"
                )
                return "exit_without_documents"

            logger.info(
                f"❌ No documents found (attempt {rewrite_attempts + 1}), improving query"
            )
            return "improve_search_query"

        if rewrite_attempts >= MAX_REWRITE_ATTEMPTS:
            logger.warning(
                "⚠️ Max rewrite attempts reached, proceeding with available documents"
            )
            return "grade_documents_for_task"

        logger.info("✅ Found vector context, evaluating relevance")
        return "grade_documents_for_task"

    def _grade_documents_for_task(
        self, state: TaskRAGState, config: RunnableConfig
    ) -> TaskRAGState:
        rewrite_attempts = state.get("rewrite_attempts", 0)
        task_prompt = state["task_prompt"]
        human_prompt = state["human_prompt"]

        if rewrite_attempts >= MAX_REWRITE_ATTEMPTS:
            logger.warning("🚨 Emergency exit: forcing task execution")
            steps = self._append_step(state, "grade_documents_emergency_exit")
            return state | {
                "documents": [],
                "grade": "execute_task",
                "steps": steps,
            }

        messages = state.get("messages", [])
        documents = self._get_documents_from_messages(messages)
        if not documents:
            steps = self._append_step(state, "grade_documents_no_docs")
            return state | {
                "documents": [],
                "grade": "improve_search_query",
                "steps": steps,
            }

        logger.info("📊 Evaluating vector context for task completion")
        grading_prompt = TASK_DOCUMENT_GRADING_HUMAN_PROMPT.format(
            task_prompt=task_prompt, human_prompt=human_prompt, documents=documents
        )

        try:
            messages_for_llm = [
                SystemMessage(content=TASK_DOCUMENT_GRADING_PROMPT),
                HumanMessage(content=grading_prompt),
            ]

            response = self.llm.invoke(messages_for_llm)

            grade_result = (
                response.content.strip().lower()
                if isinstance(response.content, str) and response.content
                else "insufficient"
            )

            if "insufficient" in grade_result:
                logger.info("❌ Documents insufficient, improving query")
                final_grade = "improve_search_query"
            else:
                logger.info("✅ Documents sufficient for task")
                final_grade = "execute_task"

        except Exception as e:
            logger.error(f"Document grading error: {e}")
            final_grade = "execute_task"

        steps = self._append_step(state, "grade_documents_for_task_completed")

        return state | {
            "documents": documents,
            "grade": final_grade,
            "steps": steps,
        }

    def _route_after_grading(
        self, state: TaskRAGState
    ) -> Literal["execute_task", "improve_search_query"]:
        grade_result = state.get("grade", "execute_task")
        if grade_result == "improve_search_query":
            return "improve_search_query"
        return "execute_task"

    def _improve_search_query(
        self, state: TaskRAGState, config: RunnableConfig
    ) -> TaskRAGState:
        current_query = state.get("search_query", "")
        rewrite_attempts = state.get("rewrite_attempts", 0)
        new_attempts = rewrite_attempts + 1
        logger.info(f"✏️ Improving search query (attempt #{new_attempts})")

        previous_queries = [current_query] if current_query else []
        improvement_prompt = QUERY_IMPROVEMENT_HUMAN_PROMPT.format(
            task_prompt=state["task_prompt"],
            human_prompt=state["human_prompt"],
            previous_queries="\n".join([f"- {q}" for q in previous_queries]),
            attempt_number=new_attempts,
        )

        messages_for_llm = [
            SystemMessage(content=QUERY_IMPROVEMENT_PROMPT),
            HumanMessage(content=improvement_prompt),
        ]

        response = self.llm.invoke(messages_for_llm)
        improved_query = (
            response.content.strip()
            if isinstance(response.content, str) and response.content
            else current_query
        )
        logger.info(f"🔄 New query: {improved_query}")

        steps = self._append_step(state, f"improve_search_query_attempt_{new_attempts}")
        tool_call = {
            "name": "retrieve related docs",
            "args": {"query": improved_query},
            "id": f"call_{new_attempts}",
        }
        ai_message = AIMessage(
            content="Searching with improved query", tool_calls=[tool_call]
        )

        return state | {
            "messages": [ai_message],
            "search_query": improved_query,
            "generation": "",
            "documents": [],
            "grade": "",
            "steps": steps,
            "rewrite_attempts": new_attempts,
        }

    def _execute_task(
        self, state: TaskRAGState, config: RunnableConfig
    ) -> TaskRAGState:
        rewrite_attempts = state.get("rewrite_attempts", 0)
        logger.info(
            f"💡 Executing task with vector context ({rewrite_attempts} rewrites)"
        )

        messages = state.get("messages", [])
        documents = self._get_documents_from_messages(messages)
        vector_context = (
            "\n\n".join(documents)
            if documents
            else "No relevant documents found in the knowledge base."
        )

        execution_prompt = TASK_EXECUTION_HUMAN_PROMPT.format(
            human_prompt=state["human_prompt"],
            vector_context=vector_context,
        )

        messages_for_llm = [
            SystemMessage(content=state["task_prompt"]),
            HumanMessage(content=execution_prompt),
        ]
        structured_output_schema = config.get("metadata", {}).get(
            "structured_output_schema"
        )
        logger.info(f"🔍 Using LLM: {self.llm.model_name}")

        if structured_output_schema:
            logger.info(
                f"ℹ️ Using structured output: {structured_output_schema.__name__}"
            )
            structured_llm = self.llm.with_structured_output(structured_output_schema)
            result_content = structured_llm.invoke(messages_for_llm, config=config)
        else:
            result_content = "Task execution failed"

        steps = self._append_step(state, "execute_task_completed")
        ai_message = AIMessage(content=str(result_content))

        return state | {
            "generation": result_content,  # type: ignore
            "messages": [ai_message],
            "documents": documents,
            "grade": "",
            "steps": steps,
        }

    def _exit_without_documents(
        self, state: TaskRAGState, config: RunnableConfig
    ) -> TaskRAGState:
        logger.warning(
            "🚫 Exiting RAG graph - no relevant documents found after 2 attempts"
        )

        steps = self._append_step(state, "exit_without_documents")
        result_content = NO_DOCUMENTS_FOUND
        ai_message = AIMessage(content=str(result_content))

        return state | {
            "generation": result_content,
            "messages": [ai_message],
            "documents": [],
            "grade": "",
            "steps": steps,
            "exit_without_documents": True,
        }

    def build_task_rag_graph(self):
        workflow = StateGraph(TaskRAGState)

        dynamic_retriever_tool = create_dynamic_retriever_tool(
            workspace_id=self.workspace_id,
            score_threshold=self.score_threshold,
            asset_ids=self.asset_ids,
        )
        retrieve_node = ToolNode([dynamic_retriever_tool])

        workflow.add_node("generate_search_query", self._generate_search_query)
        workflow.add_node("retrieve", retrieve_node)
        workflow.add_node("check_documents_found", self._check_documents_found)
        workflow.add_node("grade_documents_for_task", self._grade_documents_for_task)
        workflow.add_node("improve_search_query", self._improve_search_query)
        workflow.add_node("execute_task", self._execute_task)
        workflow.add_node("exit_without_documents", self._exit_without_documents)

        workflow.add_edge(START, "generate_search_query")
        workflow.add_edge("generate_search_query", "retrieve")

        workflow.add_conditional_edges(
            "retrieve",
            self._check_documents_found,
            {
                "grade_documents_for_task": "grade_documents_for_task",
                "improve_search_query": "improve_search_query",
                "exit_without_documents": "exit_without_documents",
            },
        )
        workflow.add_conditional_edges(
            "grade_documents_for_task",
            self._route_after_grading,
            {
                "execute_task": "execute_task",
                "improve_search_query": "improve_search_query",
            },
        )
        workflow.add_edge("execute_task", END)
        workflow.add_edge("exit_without_documents", END)
        workflow.add_edge("improve_search_query", "retrieve")

        return workflow.compile()


def build_task_rag_graph(
    llm: ChatOpenAI,
    workspace_id: int,
    score_threshold: float,
    asset_ids: list[int] | None = None,
) -> CompiledStateGraph[TaskRAGState, None, TaskRAGState, TaskRAGState]:
    task_rag_graph = TaskRAGGraph(
        llm=llm,
        workspace_id=workspace_id,
        score_threshold=score_threshold,
        asset_ids=asset_ids,
    )
    return task_rag_graph.build_task_rag_graph()
