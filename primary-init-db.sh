#!/bin/bash
set -e

dolt config --global --add user.name "myprimary"
dolt config --global --add user.email "myprimary@me.com"
dolt creds use nq8pmsqpt6thjvi6hbtj6jprt25msddjiu62dpdp446009rsebs0

dolt sql <<-EOSQL
    CREATE USER root@'%' IDENTIFIED BY 'root';
    GRANT ALL ON *.* TO root@'%';
    CREATE USER 'monitor'@'%' IDENTIFIED BY 'monitor';
    GRANT SELECT ON sys.* TO 'monitor'@'%';
    GRANT SELECT ON performance_schema.* TO 'monitor'@'%';
    GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
    CALL DOLT_CLONE('coffeegoddd/read_replication_example', 'read_replication_example');
    USE read_replication_example;
    SET @@PERSIST.dolt_replicate_to_remote = 'origin';
EOSQL
