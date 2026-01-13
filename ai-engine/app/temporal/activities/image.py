"""Image processing activities - clean interface using services."""

from temporalio import activity

from services.image import ImageAnalysisService, ImageIndexingService
from models.activity_types.image_analyze import ImageAnalyzeInput
from models.activity_types.image_index_in_vector_db import ImageIndexInVectorDbInput


@activity.defn
def image_analyze_file(input_dict: dict) -> str:
    input = ImageAnalyzeInput(**input_dict)
    activity.logger.info(f"Starting to analyze image asset {input.asset_id}")

    output_key = ImageAnalysisService.analyze_image(input)
    activity.logger.info(f"Analyzed image asset {input.asset_id}")

    return output_key


@activity.defn
def image_index_in_vector_db(input_dict: dict) -> str:
    input = ImageIndexInVectorDbInput(**input_dict)
    activity.logger.info(f"Starting to index image asset {input.asset_id}")

    document_id = ImageIndexingService.index_image(input)
    activity.logger.info(f"Indexed image asset {input.asset_id}")

    return document_id
