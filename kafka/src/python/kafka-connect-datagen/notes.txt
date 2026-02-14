
1. create a new Dockerfile.datagen file which extends 
   the confluentinc/cp-kafka-connect-base:6.1.4 image 
   and uses the confluent-hub cli to install the datagen
   connector confluentinc/kafka-connect-datagen:0.4.0

2. update the docker-compose.yml file to use the Dockerfile.datagen

3. start the docker compose services

docker-compose up -d

4. use the rest api /connector-plubins to get a list of the available plugins install

 * note that io.confluent.kafka.connect.datagen.DatagenConnector will be present

http :8083/connector-plugins -b

5. define a schema representing technologists to be created by your 

   See schema spec on github https://github.com/confluentinc/avro-random-generator#schema-annotations

{
  "type": "record",
  "name": "technologist",
  "fields": [
    {
      "name": "firstName",
      "type": {
        "type": "string",
        "arg.properties": {
          "options": ["Bill", "Sue", "Pat", "Jo"]
        }
      }
    }, 
    {
      "name": "lastName",
      "type": {
        "type": "string",
        "arg.properties": {
          "options": ["Smitch", "Adams", "Murphy", "Patel"]
        }
      }
    },
    {
      "name": "lastName",
      "type": {
        "type": "string",
        "arg.properties": {
          "options": ["Jr Engineer", "Sr Engineer", "Prin Engineer"]
        }
      }
    }
  ]
}

6. Create a JSON config file to define an instance of the datagen connector
   containing the schema.string field with the collapsed string representation
   of the schema defined above.

   collapsed schema string

  {\"type\": \"record\",\"name\": \"technologist\",\"fields\":[{\"name\": \"firstName\",\"type\":{\"type\": \"string\",\"arg.properties\":{\"options\":[\"Bill\",\"Sue\",\"Pat\",\"Jo\"]}}},{\"name\":\"lastName\",\"type\":{\"type\":\"string\",\"arg.properties\":{\"options\":[\"Smitch\",\"Adams\",\"Murphy\",\"Patel\",\"Brown\"]}}},{\"name\":\"title\",\"type\":{\"type\":\"string\",\"arg.properties\":{\"options\":[\"Jr Engineer\",\"Sr Engineer\",\"Prin Engineer\"]}}}]}


   json config file technologists.json

   {
     "name": "technologists",
     "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
     "kafka.topic": "technologists",
     "schema.string":"{\"type\":\"record\",\"name\":\"technologist\",\"fields\":[{\"name\":\"firstName\",\"type\":{\"type\":\"string\",\"arg.properties\":{\"options\":[\"Bill\",\"Sue\",\"Pat\",\"Jo\"]}}},{\"name\": \"lastName\",\"type\":{\"type\": \"string\",\"arg.properties\": {\"options\":[\"Smitch\",\"Adams\",\"Murphy\",\"Patel\",\"Brown\"]}}},{\"name\":\"title\"\"type\":{\"type\":\"string\",\"arg.properties\":{\"options\":[\"Jr Engineer\",\"Sr Engineer\",\"Prin Engineer\"]}}}]}",
     "schema.keyfield": "lastName",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "value.converter.schemas.enable": "false",
     "max.interval": 1000,
     "iterations": 1000,
     "tasks.max": 1
   }

7. create a technologist topic to write to.

docker exec -it cli-tools kafka-topics --bootstrap-server broker0:29092 --create --topic technologists --partitions 3 --replication-factor 3


8. start a datagen connector running using the technologists.json config and
   the kafak connect rest api

http PUT :8083/connectors/technologists/config @technologists.json -b

9. conume with avro cli

docker exec -it schema-registry kafka-avro-console-consumer --bootstrap-server broker0:29092 --topic technologists --property "schema.registry.url=http://localhost:8081" --from-beginning

10. check status, pause, and resume the connector worker


http :8083/connectors/technologists/status -b
http PUT :8083/connectors/technologists/pause -b
http PUT :8083/connectors/technologists/resume -b
http :8083/connectors/technologists/status -b

11. delete the running connector

http DELETE :8083/connectors/technologists -b
