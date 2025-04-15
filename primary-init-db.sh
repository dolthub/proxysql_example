#!/bin/bash
set -e

dolt config --global --add user.name "myprimary"
dolt config --global --add user.email "myprimary@me.com"

dolt sql <<-EOSQL
    CREATE USER primary_user@'%' IDENTIFIED BY 'password';
    GRANT ALL ON *.* TO primary_user@'%';
    CALL DOLT_CLONE('coffeegoddd/read_replication_example', 'read_replication_example');
    USE read_replication_example;
    SET @@PERSIST.dolt_replicate_to_remote = 'origin';
EOSQL
