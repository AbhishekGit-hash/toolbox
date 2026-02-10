
list-topics:
	kafka-topics --list --bootstrap-server broker0:29092,broker1:29093,broker2:29094

create-topics:
	kafka-topics --create --bootstrap-server broker0:29092 --topic people --partitions 3 --replication-factor 3

describe-topics:
	kafka-topics --describe --bootstrap-server broker0:29092 --topic people

delete-topics:
	kafka-topics --delete --bootstrap-server broker0:29092 --topic people