from typing import Optional
from pydantic import BaseModel


class Person(BaseModel):
  first_name: Optional[str]
  last_name: Optional[str]
  title: str

