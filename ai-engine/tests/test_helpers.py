"""Simple test helpers for agent testing."""

from contextlib import contextmanager
from pathlib import Path
from typing import Any
import vcr as vcr_module
from langchain_core.tools import Tool
from core.logging import logger
from models.llm import ModelDefinition
from models.telemetry import TelemetryContext
from constants import SectionType
from services import PayloadService
from agents.common.rag.tools import RetrieveDocsInput, custom_document_concatenation
from tests.fixtures.rag_documents import generate_documents_for_domain


def before_record_request(request):
    if request.uri.startswith("http://qdrant:6333/collections/workspace_test_1/points"):
        logger.info("Before record request: >>>>>>>>>>>>")
        logger.info(f"Request: {request.method} {request.uri}")
        logger.info(f"Request: {request.body}")
    return request


vcr = vcr_module.VCR(
    filter_headers=[
        ("authorization", "REDACTED"),
        ("x-api-key", "REDACTED"),
        ("x-openrouter-api-key", "REDACTED"),
    ],
    filter_query_parameters=[
        ("api_key", "REDACTED"),
    ],
    cassette_library_dir="tests/cassettes",
    # before_record_request=before_record_request,
    record_mode="once",
    match_on=["method", "scheme", "host", "port", "path", "query", "body"],
)


def get_test_files():
    file_names = ["example.py", "example.java", "example.rb", "example.js"]
    files = []
    for i, file_name in enumerate(file_names):
        content = (Path(__file__).parent / "fixtures" / file_name).read_text()
        files.append(
            {
                "id": i + 1,
                "name": file_name,
                "path": file_name,
                "size": len(content),
                "content": content,
            }
        )
    return files


def get_test_document():
    document_name = "document.pdf"
    file_path = Path(__file__).parent / "fixtures" / document_name
    content_bytes = file_path.read_bytes()

    return {
        "id": 1,
        "name": document_name,
        "path": document_name,
        "size": len(content_bytes),
        "content": content_bytes,
    }


def create_telemetry_context(test_name: str):
    return TelemetryContext(
        session_id=f"test-{test_name}-session",
        tags=["test", test_name],
        metadata={"workspace_id": 1, "operation_type": "test"},
    )


def correct_naming(val):
    if isinstance(val, SectionType):
        return (
            val.prompt_name.replace("/", "-")
            .replace(":", "-")
            .replace("_", "-")
            .replace(".", "-")
        )
    elif isinstance(val, dict):
        return (
            val["name"]
            .replace("/", "-")
            .replace(":", "-")
            .replace("_", "-")
            .replace(".", "-")
        )
    elif isinstance(val, ModelDefinition):
        return (
            val.identifier.replace("/", "-")
            .replace(":", "-")
            .replace("_", "-")
            .replace(".", "-")
        )
    else:
        return (
            val.replace("/", "-").replace(":", "-").replace("_", "-").replace(".", "-")
        )


def get_gemini_3_flash_model():
    return ModelDefinition(
        id=1,
        name="Gemini 3 Flash",
        identifier="google/gemini-3-flash-preview",
        family="google",
        instructor_mode="JSON",
        context_length=1000000,
    )


def get_all_test_models():
    return [get_gemini_3_flash_model()]


def get_vision_test_models():
    """Get only models that support vision/image input."""
    return [get_gemini_3_flash_model()]


def check_keys(dict, model):
    output = model(**dict)
    assert isinstance(output, model)
    for key in model.model_fields.keys():
        assert key in dict, f"Key {key} not found in dict"
    return True


@contextmanager
def use_cassette(*args):
    cassette_name = f"{'/'.join(map(correct_naming, args))}.yml"
    with vcr.use_cassette(cassette_name) as cassette:
        yield cassette


def mock_rag_retriever(mocker, domain_name: str, entity_description: str) -> None:
    def mock_retrieve_documents(query: str) -> str:
        documents = generate_documents_for_domain(domain_name, entity_description)
        return custom_document_concatenation(documents)

    mock_tool = Tool(
        name="retrieve related docs",
        description="Mock retriever for tests",
        func=mock_retrieve_documents,
        args_schema=RetrieveDocsInput,
    )

    mocker.patch(
        "agents.common.rag.task_graph.create_dynamic_retriever_tool",
        return_value=mock_tool,
    )


class PayloadHelper:
    @staticmethod
    def store_obj(obj: dict, key: str) -> str:
        return PayloadService.store_json(obj, key)

    @staticmethod
    def load(key: str) -> Any:
        return PayloadService.load_json(key)
