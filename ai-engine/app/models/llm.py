from pydantic import BaseModel


class ModelDefinition(BaseModel):
    id: int
    name: str
    identifier: str
    family: str | None = None
    instructor_mode: str | None = None
    context_length: int | None = None

