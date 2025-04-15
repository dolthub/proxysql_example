#!/bin/bash
set -e

dolt config --global --add user.name "myreplica1"
dolt config --global --add user.email "myreplica1@me.com"

dolt sql <<-EOSQL
    CREATE USER replica_1_user@'%' IDENTIFIED BY 'password';
    GRANT ALL ON *.* TO replica_1_user@'%';
    CALL DOLT_CLONE('coffeegoddd/read_replication_example', 'read_replication_example');
    USE read_replication_example;
    SET @@PERSIST.dolt_read_replica_remote = 'origin';
    SET @@PERSIST.dolt_replicate_all_heads = 1;
EOSQL
