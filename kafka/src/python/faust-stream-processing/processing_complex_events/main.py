import faust
import random

app = faust.App("objects-demo",
  topic_replication_factor=3,
  topic_partitions=3)

class Greeting(faust.Record):
  message: str
  greeter: str

greetings_topic = app.topic("greetings-event", 
                          value_type=Greeting, key_type=str, key_serializer='raw')

@app.timer(interval=5)
async def generate_greeting():
  prefix = random.choice(["Hi", "Hello", "Howdy"])
  recipient = random.choice(["Deepika", "Bob", "Jo"])
  greeting = Greeting(message=f"{prefix} {recipient}", greeter=random.choice(["Bill", "Sue"]))
  await greetings_topic.send(key=greeting.greeter, value=greeting)

@app.agent(greetings_topic)
async def process_greetings(stream: faust.StreamT[Greeting]):
  async for key, value in stream.items():
    print(f"Greeting is '{value.message}' from '{key}'")
