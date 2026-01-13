from typing import Final

from langchain_core.documents import Document
from langchain_core.tools import Tool
from langchain_openai import OpenAIEmbeddings
from langchain_qdrant import QdrantVectorStore
from core.logging import logger
from pydantic import BaseModel, Field

from vector_engine.core import VectorClient
from vector_engine.core.config import VectorCoreConfig
from vector_engine.core.models import VectorSearchFilter
from vector_engine.indexing.strategies.base_strategy import VectorConfig

MMR_SEARCH_TYPE: Final[str] = "mmr"
TOP_K_RESULTS: Final[int] = 8


class RetrieveDocsInput(BaseModel):
    query: str = Field(description="Search query to find relevant documents")


def custom_document_concatenation(documents: list[Document]) -> str:
    if not documents:
        return "No relevant documents found."

    logger.info(
        f"📄 Retrieved {len(documents)} documents ({sum(len(doc.page_content) for doc in documents)} chars)"
    )
    concatenated_parts = []
    for i, doc in enumerate(documents, 1):
        separator = f"\n--- Document {i} ---\n"
        content = doc.page_content
        concatenated_parts.append(f"{separator}{content}")

    result = "\n\n".join(concatenated_parts)
    return result


def create_dynamic_retriever_tool(
    workspace_id: int, score_threshold: float, asset_ids: list[int] | None = None
) -> Tool:
    vector_engine = VectorClient()
    vector_client = vector_engine.get_client()
    vector_config = VectorConfig(name="semantic_description")
    embeddings = OpenAIEmbeddings(model=vector_config.embedding_model)

    config = VectorCoreConfig()
    qdrant_collection_name = config.get_collection_name(workspace_id)

    search_filter = VectorSearchFilter(workspace_id=workspace_id, asset_ids=asset_ids)
    qdrant_filter = search_filter.to_qdrant_filter()

    vectorstore = QdrantVectorStore(
        client=vector_client,
        collection_name=qdrant_collection_name,
        embedding=embeddings,
        content_payload_key="content",
    )
    retriever = vectorstore.as_retriever(
        search_type=MMR_SEARCH_TYPE,
        search_kwargs={
            "k": TOP_K_RESULTS,
            "score_threshold": score_threshold,
            "filter": qdrant_filter,
        },
    )

    def retrieve_documents(query: str) -> str:
        logger.info(
            f"🔍 Searching in collection: {qdrant_collection_name} with filter: {qdrant_filter} "
            f"with score threshold: {score_threshold}"
        )
        documents = retriever.invoke(query)
        return custom_document_concatenation(documents)

    return Tool(
        name="retrieve related docs",
        description=f"Search for relevant documents in workspace {workspace_id} collection. Input should be a search query string.",
        func=retrieve_documents,
        args_schema=RetrieveDocsInput,
    )
