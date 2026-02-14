
import os
import uuid
from typing import List

from dotenv import load_dotenv
from fastapi import FastAPI
from faker import Faker
from kafka import KafkaAdminClient
from kafka.admin import NewTopic
from kafka.errors import TopicAlreadyExistsError
from kafka.producer import KafkaProducer


from commands import CreatePeopleCommand
from entities import Person


load_dotenv(verbose=True)

app = FastAPI()

@app.on_event('startup')
async def startup_event():
  client = KafkaAdminClient(bootstrap_servers=os.environ['BOOTSTRAP_SERVERS'])
  try:
    topic = NewTopic(name=os.environ['TOPICS_PEOPLE_BASIC_NAME'],
                    num_partitions=int(os.environ['TOPICS_PEOPLE_BASIC_PARTITIONS']),
                    replication_factor=int(os.environ['TOPICS_PEOPLE_BASIC_REPLICAS']))
    client.create_topics([topic])
  except TopicAlreadyExistsError as e:
    print(e)
  finally:
    client.close()


def make_producer():
  producer = KafkaProducer(bootstrap_servers=os.environ['BOOTSTRAP_SERVERS'])
  return producer


@app.post('/api/people', status_code=201, response_model=List[Person])
async def create_people(cmd: CreatePeopleCommand):
  people: List[Person] = []
  faker = Faker()
  producer = make_producer()

  for _ in range(cmd.count):
    person = Person(id=str(uuid.uuid4()), name=faker.name(), title=faker.job().title())
    people.append(person)
    producer.send(topic=os.environ['TOPICS_PEOPLE_BASIC_NAME'],
                key=person.title.lower().replace(r's+', '-').encode('utf-8'),
                value=person.json().encode('utf-8'))

  producer.flush()

  return people


