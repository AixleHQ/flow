"""Constants module for AI Engine.

All workflow and business logic constants.
Safe to import in Temporal workflows (sandbox-compatible).
"""

from .code_report_sections import SECTION_TYPES, SectionType, get_section_types
from .workflows import Workflows

__all__ = [
    "Workflows",
    "SECTION_TYPES",
    "SectionType",
    "get_section_types",
]
