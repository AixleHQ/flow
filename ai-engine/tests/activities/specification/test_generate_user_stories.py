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
from agents.specification.user_story_extraction_agent import UserStoryExtractionResult
from agents.common.rag import NoDocumentsFoundError
from app.temporal.activities import generate_user_stories
from models.llm import ModelDefinition

TEST_VERSION_ID = 1
TEST_FEATURE_ID = 2001
TEST_FEATURE_NAME = "Test Feature Name"
UNEXPECTED_RETURN_OBJECT = {"invalid_field": "invalid_value"}
NON_EXISTENT_KEY = "temporal:nonexistent_key:abc123"

models = get_all_test_models()


class TestGenerateUserStoriesActivity(TestBase):
    def _create_activity_input(
        self,
        model: ModelDefinition,
        version_id: int | None = None,
        feature_id: int | None = None,
        feature_name: str | None = None,
        feature_description: str | None = None,
        domain_name: str | None = None,
    ) -> dict[str, Any]:
        version_id = version_id or TEST_VERSION_ID
        feature_id = feature_id or TEST_FEATURE_ID

        ruby_obj = self.ruby_client.feature_context.create(
            version_id=version_id,
            feature_id=feature_id,
            feature_name=feature_name,
            feature_description=feature_description,
            domain_name=domain_name,
        )
        ruby_obj_key = self.payload_service.store_obj(
            ruby_obj, f"user_story_context_v{version_id}_f{feature_id}"
        )

        return {
            "feature_context_payload_key": ruby_obj_key,
            "user_story_extraction_model": model,
        }

    def _mock_rag_retriever(
        self, mocker: Any, domain_name: str, feature_name: str
    ) -> None:
        mock_rag_retriever(mocker, domain_name, f"Feature: {feature_name}")

    @pytest.mark.parametrize(
        "model",
        [(model) for model in models],
        ids=correct_naming,
    )
    @pytest.mark.vcr
    def test_generate_user_stories_with_vcr(self, model, mocker):
        domain_name = "User Authentication"
        feature_name = "User Login"
        feature_description = "Allow users to authenticate with email and password"

        self._mock_rag_retriever(mocker, domain_name, feature_name)
        activity_input = self._create_activity_input(
            model,
            feature_name=feature_name,
            feature_description=feature_description,
            domain_name=domain_name,
        )

        with use_cassette("generate_user_stories", model):
            activity_result = generate_user_stories(activity_input)
        assert activity_result is not None

        stored_result = self.payload_service.load(activity_result)
        assert isinstance(stored_result, dict)
        assert "feature_id" in stored_result
        assert "user_stories" in stored_result
        assert isinstance(stored_result["user_stories"], list)

    def test_generate_user_stories_full_flow(self, mocker):
        activity_input = self._create_activity_input(
            models[0], feature_id=TEST_FEATURE_ID
        )
        fake_user_stories = self.client.user_stories.create_batch(3)
        fake_user_story_result = UserStoryExtractionResult(
            user_stories=fake_user_stories
        )

        mocker.patch(
            "agents.common.rag.tools.create_dynamic_retriever_tool",
            return_value=mocker.MagicMock(),
        )

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = fake_user_story_result
        mocker.patch(
            "services.specification.user_story_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_user_stories(activity_input)

        stored_result = self.payload_service.load(activity_result)

        assert stored_result["feature_id"] == TEST_FEATURE_ID
        assert len(stored_result["user_stories"]) == len(fake_user_stories)
        for i, user_story in enumerate(stored_result["user_stories"]):
            assert user_story["name"] == fake_user_stories[i].name
            assert user_story["description"] == fake_user_stories[i].description
            assert user_story["justification"] == fake_user_stories[i].justification

    def test_generate_user_stories_missing_context_in_redis(self):
        activity_input = {
            "feature_context_payload_key": NON_EXISTENT_KEY,
            "user_story_extraction_model": models[0],
        }

        with pytest.raises(NonRetryableError) as exc_info:
            generate_user_stories(activity_input)

        assert "No context provided for user story generation" in str(exc_info.value)

    def test_generate_user_stories_invalid_ruby_object(self):
        invalid_ruby_obj = {
            "version_id": TEST_VERSION_ID,
            "workspace_id": "invalid_workspace_id",
        }
        ruby_obj_key = self.payload_service.store_obj(
            invalid_ruby_obj, f"user_story_context_{TEST_VERSION_ID}"
        )

        activity_input = {
            "feature_context_payload_key": ruby_obj_key,
            "user_story_extraction_model": models[0],
        }

        with pytest.raises(ValidationError) as exc_info:
            generate_user_stories(activity_input)

        errors = exc_info.value.errors()
        error_fields = {error["loc"][0] for error in errors}

        assert "asset_ids" in error_fields
        assert "feature_id" in error_fields
        assert "feature_name" in error_fields
        assert "domain_name" in error_fields

    def test_generate_user_stories_no_context_error(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mocker.patch(
            "services.payload_service.PayloadService.load_object", return_value=None
        )

        with pytest.raises(NonRetryableError) as exc_info:
            generate_user_stories(activity_input)

        assert "No context provided for user story generation" in str(exc_info.value)

    def test_generate_user_stories_no_documents_found(self, mocker):
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
            "services.specification.user_story_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_user_stories(activity_input)

        assert activity_result is None

    def test_generate_user_stories_returns_none_when_empty(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = UserStoryExtractionResult(
            user_stories=[]
        )
        mocker.patch(
            "services.specification.user_story_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        activity_result = generate_user_stories(activity_input)

        assert activity_result is None

    def test_generate_user_stories_task_rag_agent_called_correctly(self, mocker):
        activity_input = self._create_activity_input(
            models[0], feature_name=TEST_FEATURE_NAME
        )
        fake_user_stories = self.client.user_stories.create_batch(2)
        fake_user_story_result = UserStoryExtractionResult(
            user_stories=fake_user_stories
        )

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = fake_user_story_result
        mocker.patch(
            "services.specification.user_story_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )
        mock_execute = mock_agent.execute_task

        generate_user_stories(activity_input)

        mock_execute.assert_called_once()

        call_kwargs = mock_execute.call_args.kwargs
        context_params = call_kwargs.get("context_params", {})
        assert context_params["feature_name"] == TEST_FEATURE_NAME
        assert "domain_name" in context_params
        assert "feature_description" in context_params

    def test_generate_user_stories_structured_output_validation(self, mocker):
        activity_input = self._create_activity_input(models[0])

        mock_agent = mocker.MagicMock()
        mock_agent.execute_task.return_value = UNEXPECTED_RETURN_OBJECT
        mocker.patch(
            "services.specification.user_story_generation_service.TaskRAGAgent",
            return_value=mock_agent,
        )

        with pytest.raises(ValueError) as exc_info:
            generate_user_stories(activity_input)

        assert str(exc_info.value) == (
            f"Expected UserStoryExtractionResult, got {type(UNEXPECTED_RETURN_OBJECT)}"
        )
