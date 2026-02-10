
list-topics:
	kafka-topics --list --bootstrap-server broker0:29092,broker1:29093,broker2:29094

create-topics:
	kafka-topics --create --bootstrap-server broker0:29092 --topic people --partitions 3 --replication-factor 3

describe-topics:
	kafka-topics --describe --bootstrap-server broker0:29092 --topic people

delete-topics:
	kafka-topics --delete --bootstrap-server broker0:29092 --topic people

create-topic-retention:
	kafka-topics --create --bootstrap-server broker0:29092 --topic experiments --config retention.ms=36000

create-compacted-topic:
	kafka-topics --create --bootstrap-server broker0:29092 --topic experiments.latest --config cleanup.policy=compact

change-topic-retention:
	kafka-configs --bootstrap-server broker0:29092 --alter --entity-type topics --entity-name experiments --add-config retention.ms=120000

view-topic-configs:
	kafka-configs --describe --all --bootstrap-server broker0:29092 --topic experiments
	kafka-configs --describe --all --bootstrap-server broker0:29092 --topic experiments.latest