# AI Engine Tests

## Test Structure

```
tests/
├── conftest.py              # Pytest configuration and fixtures
├── activities/              # Activity tests
│   ├── test_workspace_activities.py
│   └── test_codebase_activities.py
└── cassettes/              # VCR cassettes (HTTP recordings)
    └── *.yaml
```

## Running Tests

### All Tests
```bash
docker compose exec temporal-worker-python pytest tests/ -v
```

### Specific Test File
```bash
docker compose exec temporal-worker-python pytest tests/activities/test_workspace_activities.py -v
```

### Specific Test
```bash
docker compose exec temporal-worker-python pytest tests/activities/test_workspace_activities.py::TestWorkspaceGetPresetsActivity::test_returns_all_required_fields -v
```

### With Coverage
```bash
docker compose exec temporal-worker-python pytest tests/ --cov=activities --cov=services --cov-report=html
```

### Skip Slow Tests
```bash
docker compose exec temporal-worker-python pytest tests/ -v -m "not slow"
```

## Test Markers

- `@pytest.mark.unit` - Unit tests (no external dependencies)
- `@pytest.mark.integration` - Integration tests (requires DB, Temporal)
- `@pytest.mark.slow` - Slow tests (real LLM calls)
- `@pytest.mark.vcr()` - Uses VCR cassettes for HTTP recording

## VCR Cassettes

### What are VCR Cassettes?

VCR records HTTP interactions (LLM API calls) and replays them in subsequent test runs:
- **First run**: Makes real API calls, saves responses to `tests/cassettes/*.yaml`
- **Subsequent runs**: Replays saved responses (no API calls, no cost!)

### Recording New Cassettes

```bash
# Delete old cassettes to force re-recording
rm tests/cassettes/test_analyze_file_with_real_llm.yaml

# Run test - will make real API call and record
docker compose exec temporal-worker-python pytest tests/activities/test_codebase_activities.py::test_analyze_file_with_real_llm -v

# Future runs will use the cassette
```

### Refreshing All Cassettes

```bash
# Delete all cassettes
rm -rf tests/cassettes/

# Re-run tests (will record new cassettes)
docker compose exec temporal-worker-python pytest tests/ -v --vcr-record=all
```

## Testing Strategy

### 1. Unit Tests (Fast, No Dependencies)

Test activities with mocked services:
```python
def test_analyze_file_with_mock(mock_file_data, mocker):
    # Mock service
    mock_service = mocker.patch('activities.codebase.FileAnalysisService')
    mock_service.return_value.analyze_file.return_value = {...}

    # Call activity
    result = code_base__analyze_file(mock_file_data)

    # Assert
    assert result['file_id'] == 1
```

**Benefits:**
- ⚡ Fast (milliseconds)
- 🔒 Isolated (no external deps)
- 💰 Free (no API calls)

### 2. Integration Tests with VCR (Medium Speed)

Test with real agents but recorded responses:
```python
@pytest.mark.vcr()
def test_analyze_file_with_real_llm(mock_file_data):
    # First run: real API call + record
    # Subsequent: replay from cassette
    result = code_base__analyze_file(mock_file_data)
    assert result['language'] == 'Python'
```

**Benefits:**
- 🎯 Real agent behavior
- 💰 Free after first run (uses cassettes)
- 🔁 Deterministic (same response every time)

### 3. Integration Tests (Slow, requires setup)

Test full workflow with database:
```python
@pytest.mark.integration
def test_full_file_processing(db_session, code_base_item):
    # Requires: DB, Temporal workers running
    # Tests real end-to-end flow
    ...
```

**Use sparingly** - only for critical flows

## Writing New Tests

### Activity Test Template

```python
from activities.my_module import my_activity

class TestMyActivity:
    def test_with_mock(self, mocker):
        \"\"\"Fast unit test with mocked dependencies.\"\"\"
        # Mock external service
        mock_service = mocker.patch('activities.my_module.MyService')
        mock_service.return_value.do_work.return_value = {'result': 'ok'}

        # Call activity
        result = my_activity({'input': 'data'})

        # Verify
        assert result['result'] == 'ok'

    @pytest.mark.vcr()
    def test_with_vcr(self):
        \"\"\"Integration test with VCR recording.\"\"\"
        result = my_activity({'input': 'data'})

        # First run: real API call
        # Next runs: replay from cassette
        assert result is not None
```

## Best Practices

1. **Mock by default** - Use `mocker` for fast tests
2. **VCR for LLM** - Record expensive API calls
3. **No DB in unit tests** - Keep tests fast
4. **Clear test names** - Describe what is tested
5. **One assertion per test** - Easy to debug failures

## Environment Variables

Tests use same config as app (`config/settings.yml`):
- `ENVIRONMENT=test`
- Database from `DB_*` env vars
- API keys from env (for VCR recording)

## CI/CD

```yaml
# In GitHub Actions
- name: Run Python tests
  run: |
    docker compose run --rm temporal-worker-python pytest tests/ -v --cov
```
Cassettes should be committed to Git for CI!


