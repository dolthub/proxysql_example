#!/bin/bash
set -e

dolt config --global --add user.name "myreplica1"
dolt config --global --add user.email "myreplica1@me.com"
dolt creds use "$DOLT_CREDS_PUBLIC_KEY"

dolt sql <<-EOSQL
    CREATE USER root@'%' IDENTIFIED BY 'root';
    GRANT ALL ON *.* TO root@'%';
    CREATE USER 'monitor'@'%' IDENTIFIED BY 'monitor';
    GRANT SELECT ON sys.* TO 'monitor'@'%';
    GRANT SELECT ON performance_schema.* TO 'monitor'@'%';
    GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
    CALL DOLT_CLONE('coffeegoddd/read_replication_example', 'read_replication_example');
    USE read_replication_example;
    SET @@PERSIST.dolt_read_replica_remote = 'origin';
    SET @@PERSIST.dolt_replicate_all_heads = 1;
EOSQL
