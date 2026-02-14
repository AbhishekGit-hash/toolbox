import faust

app = faust.App("table-demo",
  topic_replication_factor=3,
  topic_partitions=3)

class Greeting(faust.Record):
  message: str
  greeter: str

greetings_topic = app.topic("greetings-event", value_type=Greeting, key_type=str, key_serializer='raw')
greetings_table = app.Table("greetings-count", default=int)

@app.agent(greetings_topic)
async def count_greetings(stream: faust.StreamT[Greeting]):
  async for greeting in stream.group_by(Greeting.greeter):
    print(f"Greeting is '{greeting.message}' from '{greeting.greeter}'")

    greetings_table[greeting.greeter] += 1
    print(greetings_table.as_ansitable(title="Greetings Count"))
