import faust
from datetime import datetime

app = faust.App("tasks-demo",)

@app.task
async def on_startup():
  print("A task executing on startup")

@app.timer(interval=10)
async def on_interval():
  print(f"A task executing on interval at {datetime.now()}")
