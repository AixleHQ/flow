"""
String utility functions.

Common string manipulation functions used across the application.
"""

import re


def camel_to_snake(name: str) -> str:
    """
    Convert CamelCase to snake_case.

    Examples:
        CodeReport -> code_report
        SpecificationVersion -> specification_version
        UIImage -> ui_image
    """
    s1 = re.sub("(.)([A-Z][a-z]+)", r"\1_\2", name)
    s2 = re.sub("([a-z0-9])([A-Z])", r"\1_\2", s1)
    return s2.lower()
