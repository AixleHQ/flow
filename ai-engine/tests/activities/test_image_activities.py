"""Tests for image activities."""

import pytest

from tests.test_helpers import (
    get_vision_test_models,
    correct_naming,
    check_keys,
    use_cassette,
)
from models.activity_types.image_analyze import ImageAnalyzeInput, ImageAnalyzeOutput
from models.activity_types.image_index_in_vector_db import ImageIndexInVectorDbInput
from services import DumpService, PayloadService
import uuid
from app.temporal.activities import (
    image_analyze_file,
    image_index_in_vector_db,
)
from pathlib import Path

models = get_vision_test_models()


def get_test_image():
    image_name = "example-image.png"
    file_path = Path(__file__).parent.parent / "fixtures" / image_name
    image_bytes = file_path.read_bytes()

    # Store bytes and get key
    image_bytes_key = PayloadService.store_bytes(image_bytes, "test_image_bytes_1")

    return {
        "id": 1,
        "name": image_name,
        "path": image_name,
        "size": len(image_bytes),
        "image_bytes_key": image_bytes_key,
    }


@pytest.fixture
def image():
    return get_test_image()


@pytest.mark.usefixtures("mock_redis")
class TestImageAnalyzeFileActivity:
    def create_image_analyze_input(self, image, model):
        # Store image data in payload service
        image_data_key = PayloadService.store_json(image, f"test_image_{image['id']}")

        return ImageAnalyzeInput(
            image_data_key=image_data_key,
            asset_id=image["id"],
            ui_vision_model=model,
            ui_critic_model=model,
            ui_summary_model=model,
        ).model_dump()

    @pytest.mark.parametrize("model", [(model) for model in models], ids=correct_naming)
    def test_image_analyze_file(self, model, image):
        with use_cassette("image-analyze-file", image["name"], model):
            input_dict = self.create_image_analyze_input(image, model)
            output_key = image_analyze_file(input_dict)

            # Load output from payload service
            output_dict = PayloadService.load_json(output_key)

            assert check_keys(output_dict, ImageAnalyzeOutput)
            output = ImageAnalyzeOutput(**output_dict)

            # Verify output structure
            assert output.file_name == image["name"]
            assert output.file_path == image["path"]
            assert output.file_size == image["size"]
            assert len(output.functional_groups) > 0


@pytest.mark.usefixtures("mock_redis")
class TestImageIndexInVectorDbActivity:
    def image_analyze_from_dump(self, file_name, model, image):
        # For images we don't have dumps yet, create placeholder
        return ImageAnalyzeOutput(
            file_name=file_name,
            file_path=file_name,
            file_size=image["size"],
            functional_groups="Placeholder analysis",
        )

    def create_image_index_in_vector_db_input(self, image, model):
        analysis_dict = DumpService.load("image_analysis", image["name"], model.identifier)
        analysis_key = PayloadService.store_json(
            analysis_dict, f"test_analysis_{image['id']}"
        )

        return ImageIndexInVectorDbInput(
            asset_id=image["id"],
            workspace_id=1,
            analysis_key=analysis_key,
        ).model_dump()

    @pytest.mark.parametrize("model", [(model) for model in models], ids=correct_naming)
    def test_image_index_in_vector_db(self, model, mocker, image):
        mocker.patch(
            "uuid.uuid4",
            return_value=uuid.UUID(f"0000{image['id']}000-0000-0000-0000-000000000000"),
        )
        with use_cassette("image-index-in-vector-db", image["name"], model):
            input_dict = self.create_image_index_in_vector_db_input(image, model)
            document_id = image_index_in_vector_db(input_dict)

            # Verify we got a document ID back
            assert document_id is not None
            assert isinstance(document_id, str)
            assert len(document_id) > 0
