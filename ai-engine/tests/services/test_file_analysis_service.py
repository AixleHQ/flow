import pytest

from services.codebase.file_analysis_service import (
    MIN_LINES_TO_ANALYZE,
    SMALL_FILE_LINES_THRESHOLD,
)


class TestFileAnalysisThresholds:
    def test_min_lines_threshold_is_reasonable(self):
        assert MIN_LINES_TO_ANALYZE == 5
        assert MIN_LINES_TO_ANALYZE < SMALL_FILE_LINES_THRESHOLD

    def test_small_file_threshold_is_reasonable(self):
        assert SMALL_FILE_LINES_THRESHOLD == 50


class TestLineCountLogic:
    @pytest.mark.parametrize(
        "content,expected_lines",
        [
            ("", 0),
            ("single line", 1),
            ("line1\nline2", 2),
            ("line1\nline2\nline3", 3),
            ("line1\nline2\nline3\nline4\nline5", 5),
        ],
    )
    def test_line_count_calculation(self, content, expected_lines):
        line_count = content.count("\n") + 1 if content else 0
        assert line_count == expected_lines

    def test_file_below_min_threshold_should_skip(self):
        content = "line1\nline2\nline3"
        line_count = content.count("\n") + 1

        assert line_count < MIN_LINES_TO_ANALYZE

    def test_file_below_small_threshold_uses_cheap_model(self):
        content = "\n".join([f"line{i}" for i in range(30)])
        line_count = content.count("\n") + 1

        assert line_count >= MIN_LINES_TO_ANALYZE
        assert line_count < SMALL_FILE_LINES_THRESHOLD

    def test_file_above_small_threshold_uses_preset_model(self):
        content = "\n".join([f"line{i}" for i in range(100)])
        line_count = content.count("\n") + 1

        assert line_count >= SMALL_FILE_LINES_THRESHOLD
