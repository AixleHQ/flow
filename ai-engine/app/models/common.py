from pydantic import BaseModel


class StrictModel(BaseModel):
    model_config = {"extra": "forbid"}
