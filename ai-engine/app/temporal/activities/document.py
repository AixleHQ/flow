"""Document processing activities - clean interface using services."""

from temporalio import activity

from services.document import DocumentAnalysisService, DocumentIndexingService
from models.activity_types.document_analyze import DocumentAnalyzeInput
from models.activity_types.document_index_in_vector_db import (
    DocumentIndexInVectorDbInput,
)


@activity.defn
def document_analyze_file(input_dict: dict) -> str:
    input = DocumentAnalyzeInput(**input_dict)
    activity.logger.info(f"Starting to analyze document asset {input.asset_id}")

    output_key = DocumentAnalysisService.analyze_document(input)
    activity.logger.info(f"Analyzed document asset {input.asset_id}")

    return output_key


@activity.defn
def document_index_in_vector_db(input_dict: dict) -> str:
    input = DocumentIndexInVectorDbInput(**input_dict)
    activity.logger.info(f"Starting to index document asset {input.asset_id}")

    document_id = DocumentIndexingService.index_document(input)
    activity.logger.info(f"Indexed document asset {input.asset_id}")

    return document_id
