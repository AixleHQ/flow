import pytest
from pydantic import ValidationError
from typing import Any

from tests.test_helpers import (
    get_all_test_models,
    correct_naming,
    use_cassette,
    mock_rag_retriever,
)
from tests.test_base import TestBase
from temporal.wrap_error import NonRetryableError
from agents.specification.use_case_extraction_agent import UseCaseExtractionResult
from agents.common.rag import NoDocumentsFoundError
from app.temporal.activities import generate_use_cases
from models.llm import ModelDefinition

TEST_VERSION_ID = 1
TEST_USER_STORY_ID = 3001
TEST_USER_STORY_NAME = "Test User Story Name"
UNEXPECTED_RETURN_OBJECT = {"invalid_field": "invalid_value"}
NON_EXISTENT_KEY = "temporal:nonexistent_key:abc123"

models = get_all_test_models()


class TestGenerateUseCasesActivity(TestBase):
    def _create_activity_input(
        self,
        model: ModelDefinition,
        version_id: int | None = None,
        user_story_id: int | None = None,
        user_story_name: str | None = None,
        user_story_description: str | None = None,
        domain_name: str | None = None,
    ) -> dict[str, Any]:
        version_id = version_id or TEST_VERSION_ID
        user_story_id = user_story_id or TEST_USER_STORY_ID

        ruby_obj = self.ruby_client.user_story_context.create(
            version_id=version_id,
            user_story_id=user_story_id,
            user_story_name=user_story_name,
            user_story_description=user_story_description,
            domain_name=domain_name,
        )
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"use_case_context_v{version_id}_us{user_story_id}"
        )

        return {
            "user_story_context_payload_key": ruby_obj_key,
            "use_case_extraction_model": model,
        }

    def _mock_rag_retriever(
        self, mocker: Any, domain_name: str, user_story_name: str
    ) -> None:
        mock_rag_retriever(mocker, domain_name, f"User Story: {user_story_name}")

    @pytest.mark.parametrize(
        "model",
        [(model) for model in models],
        ids=correct_naming,
    )
    @pytest.mark.vcr
    def test_generate_use_cases_with_vcr(self, model, mocker):
        domain_name = "User Authentication"
        user_story_name = "User Login"
        user_story_description = "As a user, I want to log in with email and password, so that I can access my account"

        self._mock_rag_retriever(mocker, domain_name, user_story_name)
        activity_input = self._create_activity_input(
            model,
            user_story_name=user_story_name,
            user_story_description=user_story_description,
            domain_name=domain_name,
        )

        with use_cassette("generate_use_cases", model):
            activity_result = generate_use_cases(activity_input)
        assert activity_result is not None

        stored_result = self.payload_service.load(activity_result)
        assert isinstance(stored_result, dict)
        assert "user_story_id" in stored_result
        assert "use_cases" in stored_result
        assert isinstance(stored_result["use_cases"], list)

    def test_generate_use_cases_full_flow(self, mocker):
        activity_input = self._create_activity_input(
            models[0], user_story_id=TEST_USER_STORY_ID
        )
        fake_use_cases = self.client.use_cases.create_batch(3)
        fake_use_case_result = UseCaseExtractionResult(use_cases=fake_use_cases)

        mocker.patch(
            "agents.common.rag.tools.create_dynamic_retriever_tool",
            return_value=mocker.MagicMock(),
        )

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = fake_use_case_result
        mocker.patch(
            "services.specification.use_case_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_use_cases(activity_input)

        assert activity_result is not None
        stored_result = self.payload_service.load(activity_result)
        assert isinstance(stored_result, dict)
        assert "user_story_id" in stored_result
        assert "use_cases" in stored_result
        assert len(stored_result["use_cases"]) == 3

    def test_generate_use_cases_missing_context_in_redis(self, mocker):
        activity_input = {
            "user_story_context_payload_key": NON_EXISTENT_KEY,
            "use_case_extraction_model": models[0],
        }

        with pytest.raises(NonRetryableError) as exc_info:
            generate_use_cases(activity_input)

        assert "No context provided for use case generation" in str(exc_info.value)

    def test_generate_use_cases_invalid_ruby_object(self, mocker):
        invalid_ruby_obj = {
            "version_id": TEST_VERSION_ID,
            "workspace_id": "invalid_workspace_id",
        }
        ruby_obj_key = self.payload_service.store_obj(
            invalid_ruby_obj, f"use_case_context_{TEST_VERSION_ID}"
        )

        activity_input = {
            "user_story_context_payload_key": ruby_obj_key,
            "use_case_extraction_model": models[0],
        }

        with pytest.raises(ValidationError) as exc_info:
            generate_use_cases(activity_input)

        errors = exc_info.value.errors()
        error_fields = {error["loc"][0] for error in errors}

        assert "asset_ids" in error_fields
        assert "user_story_id" in error_fields
        assert "user_story_name" in error_fields
        assert "domain_name" in error_fields

    def test_generate_use_cases_no_context_error(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mocker.patch(
            "services.payload_service.PayloadService.load_object", return_value=None
        )

        with pytest.raises(NonRetryableError) as exc_info:
            generate_use_cases(activity_input)

        assert "No context provided for use case generation" in str(exc_info.value)

    def test_generate_use_cases_no_documents_found(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mocker.patch(
            "agents.common.rag.tools.create_dynamic_retriever_tool",
            return_value=mocker.MagicMock(),
        )

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.side_effect = NoDocumentsFoundError(
            "No documents found"
        )
        mocker.patch(
            "services.specification.use_case_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_use_cases(activity_input)

        assert activity_result is None

    def test_generate_use_cases_returns_none_when_empty(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = UseCaseExtractionResult(use_cases=[])
        mocker.patch(
            "services.specification.use_case_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_use_cases(activity_input)

        assert activity_result is None

    def test_generate_use_cases_task_rag_agent_called_correctly(self, mocker):
        activity_input = self._create_activity_input(
            models[0],
            user_story_name=TEST_USER_STORY_NAME,
            user_story_description="Test description",
            domain_name="Domain 17",
        )
        fake_use_cases = self.client.use_cases.create_batch(2)
        fake_use_case_result = UseCaseExtractionResult(use_cases=fake_use_cases)

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = fake_use_case_result
        mock_agent_class = mocker.patch(
            "services.specification.use_case_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        generate_use_cases(activity_input)

        mock_agent_class.assert_called_once()
        mock_agent.execute_task.assert_called_once()
        call_args = mock_agent.execute_task.call_args
        assert call_args.kwargs["structured_output_schema"] == UseCaseExtractionResult
        assert "domain_name" in call_args.kwargs["context_params"]
        assert "user_story" in call_args.kwargs["context_params"]
        assert TEST_USER_STORY_NAME in call_args.kwargs["context_params"]["user_story"]

    def test_generate_use_cases_structured_output_validation(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = UNEXPECTED_RETURN_OBJECT
        mocker.patch(
            "services.specification.use_case_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        with pytest.raises(ValueError) as exc_info:
            generate_use_cases(activity_input)

        assert "Expected UseCaseExtractionResult" in str(exc_info.value)
