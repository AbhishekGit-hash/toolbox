import logging

from kafka import KafkaAdminClient
from kafka.admin import NewTopic, ConfigResource, ConfigResourceType
from kafka.errors import TopicAlreadyExistsError
from dotenv import load_dotenv

logger = logging.getLogger()

load_dotenv(verbose=True)

def create_topic():
    pass