# proxysql_example

This demonstrates how to use Docker to run ProxySQL in front of a MySQL read replication cluster or Dolt read replication cluster.

Before you begin, be sure to remove any existing Docker volumes for the local replication cluster you want to run. For MySQL, be sure to delete
the following Docker volumes:

```bash
docker volume rm proxysql_example_mysql_primary_data
docker volume rm proxysql_example_mysql_replica_1_data
docker volume rm proxysql_example_proxysql_data
```

For Dolt, be sure to delete the following Docker volumes:

```bash
docker volume rm proxysql_example_dolt_primary_data
docker volume rm proxysql_example_dolt_primary_dolt_config
docker volume rm proxysql_example_dolt_primary_server_config
docker volume rm proxysql_example_dolt_replica_1_data
docker volume rm proxysql_example_dolt_replica_1_dolt_config
docker volume rm proxysql_example_dolt_replica_1_server_config
docker volume rm proxysql_example_proxysql_data
```

## MySQL

To run ProxySQL with a simple MySQL read replica cluster with Docker Compose run the following command:

```bash
docker compose -f mysql-docker-compose.yaml up
```

This will start three containers in Docker, `primary`, `replica-1`, and `proxysql`. Once the servers come up, you will need to
configure replication between `primary` and `replica-1`.

To do this, first connect to the `primary` and run the following SQL:

```sql
CREATE USER 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
```

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3307 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 19
Server version: 8.0.42 MySQL Community Server - GPL

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> CREATE USER 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
Query OK, 0 rows affected (0.01 sec)

mysql> GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
Query OK, 0 rows affected (0.00 sec)

mysql> FLUSH PRIVILEGES;
Query OK, 0 rows affected (0.00 sec)
```

Additionally, while connected to `primary` we can create the user ProxySQL will need to monitor the replication cluster:

```sql
CREATE USER 'monitor'@'%' IDENTIFIED BY 'monitor';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
```

```bash
mysql> CREATE USER 'monitor'@'%' IDENTIFIED BY 'monitor';
Query OK, 0 rows affected (0.01 sec)

mysql> GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
Query OK, 0 rows affected (0.01 sec)
```

Next, connect to `replica-1` and execute the following SQL to start read replication:

```sql
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='primary',
  SOURCE_USER='repl',
  SOURCE_PASSWORD='replpass',
  SOURCE_AUTO_POSITION=1;

START REPLICA;
```

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3308 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 58
Server version: 8.0.42 MySQL Community Server - GPL

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> CHANGE REPLICATION SOURCE TO
    ->   SOURCE_HOST='primary',
    ->   SOURCE_USER='repl',
    ->   SOURCE_PASSWORD='replpass',
    ->   SOURCE_AUTO_POSITION=1;
Query OK, 0 rows affected, 1 warning (0.02 sec)

mysql> 
mysql> START REPLICA;
Query OK, 0 rows affected (0.05 sec)
```

Next, you should verify that replication is working. Reconnect to the `primary` and make a write:

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3307 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 47
Server version: 8.0.42 MySQL Community Server - GPL

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Database changed
mysql> create table t1 (pk int primary key);
Query OK, 0 rows affected (0.02 sec)
```

And then go back to the replica and verify that it contains the change you just made:

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3308 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 75
Server version: 8.0.42 MySQL Community Server - GPL

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
+------------------------------------+
1 row in set (0.00 sec)
```

Now that replication is working, it's time to configure ProxySQL to monitor and route to the MySQL servers.

Because this is running in Docker, and ProxySQL requires the admin to connect on the same host its running on, use `docker exec` to shell into the running `proxysql` container:

```bash
proxysql_example % docker ps
CONTAINER ID   IMAGE                      COMMAND                  CREATED          STATUS          PORTS                               NAMES
9815e504920d   proxysql/proxysql:latest   "proxysql --initial …"   13 minutes ago   Up 13 minutes   0.0.0.0:6032-6033->6032-6033/tcp    proxysql
375d4ffa5e60   mysql:8.0                  "docker-entrypoint.s…"   13 minutes ago   Up 13 minutes   33060/tcp, 0.0.0.0:3308->3306/tcp   replica-1
feafc8cdaf79   mysql:8.0                  "docker-entrypoint.s…"   13 minutes ago   Up 13 minutes   33060/tcp, 0.0.0.0:3307->3306/tcp   primary
dustin@Dustins-MacBook-Pro-3 proxysql_example % docker exec -it 9815e504920d /bin/bash
root@9815e504920d:/#
```

Now, following the [configuration docs from ProxySQL](https://proxysql.com/documentation/proxysql-configuration/), connect to the admin port and enable monitoring by running the following SQL:

```sql
UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_username';
UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_password';
UPDATE global_variables SET variable_value='2000' WHERE variable_name IN ('mysql-monitor_connect_interval','mysql-monitor_ping_interval','mysql-monitor_read_only_interval');
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
LOAD MYSQL SERVERS TO RUNTIME;
```

```bash
root@9815e504920d:/# mysql -u admin -padmin -h 127.0.0.1 -P6032 --prompt 'ProxySQL Admin> '
Welcome to the MariaDB monitor.  Commands end with ; or \g.
Your MySQL connection id is 1
Server version: 8.0.11 (ProxySQL Admin Module)

Copyright (c) 2000, 2018, Oracle, MariaDB Corporation Ab and others.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

ProxySQL Admin> UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_username';
Query OK, 1 row affected (0.006 sec)

ProxySQL Admin> UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_password';
Query OK, 1 row affected (0.002 sec)

ProxySQL Admin> UPDATE global_variables SET variable_value='2000' WHERE variable_name IN ('mysql-monitor_connect_interval','mysql-monitor_ping_interval','mysql-monitor_read_only_interval');
Query OK, 3 rows affected (0.002 sec)

ProxySQL Admin> LOAD MYSQL VARIABLES TO RUNTIME;
Query OK, 0 rows affected (0.002 sec)

ProxySQL Admin> SAVE MYSQL VARIABLES TO DISK;
Query OK, 167 rows affected (0.008 sec)

ProxySQL Admin> LOAD MYSQL SERVERS TO RUNTIME;
Query OK, 0 rows affected (0.007 sec)
```

Next, check that the backend servers are healthy:

```bash
ProxySQL Admin> SELECT * FROM mysql_servers;
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname  | port | gtid_port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 10           | primary   | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
| 20           | replica-1 | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
2 rows in set (0.001 sec)

ProxySQL Admin> SHOW TABLES FROM monitor;
+--------------------------------------+
| tables                               |
+--------------------------------------+
| mysql_server_aws_aurora_check_status |
| mysql_server_aws_aurora_failovers    |
| mysql_server_aws_aurora_log          |
| mysql_server_connect_log             |
| mysql_server_galera_log              |
| mysql_server_group_replication_log   |
| mysql_server_ping_log                |
| mysql_server_read_only_log           |
| mysql_server_replication_lag_log     |
+--------------------------------------+
9 rows in set (0.001 sec)

ProxySQL Admin> SELECT * FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 3;
+-----------+------+------------------+-------------------------+---------------+
| hostname  | port | time_start_us    | connect_success_time_us | connect_error |
+-----------+------+------------------+-------------------------+---------------+
| primary   | 3306 | 1744846225615951 | 1811                    | NULL          |
| replica-1 | 3306 | 1744846225579795 | 1818                    | NULL          |
| primary   | 3306 | 1744846223602262 | 2020                    | NULL          |
+-----------+------+------------------+-------------------------+---------------+
3 rows in set (0.001 sec)

ProxySQL Admin> SELECT * FROM monitor.mysql_server_ping_log ORDER BY time_start_us DESC LIMIT 3;
+-----------+------+------------------+----------------------+------------+
| hostname  | port | time_start_us    | ping_success_time_us | ping_error |
+-----------+------+------------------+----------------------+------------+
| replica-1 | 3306 | 1744846233861533 | 101                  | NULL       |
| primary   | 3306 | 1744846233861442 | 176                  | NULL       |
| primary   | 3306 | 1744846231860460 | 678                  | NULL       |
+-----------+------+------------------+----------------------+------------+
3 rows in set (0.001 sec)
```

Next, run the following `INSERT` to configure the replication hostgroups in ProxySQL:

```sql
INSERT INTO mysql_replication_hostgroups (writer_hostgroup,reader_hostgroup,comment) VALUES (10,20,'cluster1');
LOAD MYSQL SERVERS TO RUNTIME;
```

```bash
ProxySQL Admin> INSERT INTO mysql_replication_hostgroups (writer_hostgroup,reader_hostgroup,comment) VALUES (10,20,'cluster1');
Query OK, 1 row affected (0.003 sec)

ProxySQL Admin> LOAD MYSQL SERVERS TO RUNTIME;
Query OK, 0 rows affected (0.007 sec)
```

And verify the read-only configuration of your backends before persisting the changes to disk:

```bash
ProxySQL Admin> SELECT * FROM monitor.mysql_server_read_only_log ORDER BY time_start_us DESC LIMIT 3;
+-----------+------+------------------+-----------------+-----------+-------+
| hostname  | port | time_start_us    | success_time_us | read_only | error |
+-----------+------+------------------+-----------------+-----------+-------+
| primary   | 3306 | 1744846433829568 | 2730            | 0         | NULL  |
| replica-1 | 3306 | 1744846433828410 | 3801            | 1         | NULL  |
| primary   | 3306 | 1744846431827261 | 10754           | 0         | NULL  |
+-----------+------+------------------+-----------------+-----------+-------+
3 rows in set (0.001 sec)

ProxySQL Admin> SELECT * FROM mysql_servers;
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname  | port | gtid_port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 10           | primary   | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
| 20           | replica-1 | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
2 rows in set (0.001 sec)

ProxySQL Admin> SAVE MYSQL SERVERS TO DISK;
Query OK, 0 rows affected (0.029 sec)

ProxySQL Admin> SAVE MYSQL VARIABLES TO DISK;
Query OK, 167 rows affected (0.008 sec)
```

Finally, your cluster should be working properly, and you can begin adding credentials for end users of your service.

To do so, connect to the primary and run the following SQL to create a sample user:

```sql
CREATE USER 'stnduser'@'%' IDENTIFIED BY 'stnduser';
GRANT ALL PRIVILEGES ON *.* TO 'stnduser'@'%';
```

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3307 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 307
Server version: 8.0.42 MySQL Community Server - GPL

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> CREATE USER 'stnduser'@'%' IDENTIFIED BY 'stnduser';
Query OK, 0 rows affected (0.02 sec)

mysql> GRANT ALL PRIVILEGES ON *.* TO 'stnduser'@'%';
Query OK, 0 rows affected (0.01 sec)
```

Then return to the ProxySQL admin shell, and run the following SQL to register this user:

```sql
INSERT INTO mysql_users(username,password,default_hostgroup) VALUES ('stnduser','stnduser',1);
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
```

```bash
ProxySQL Admin> INSERT INTO mysql_users(username,password,default_hostgroup) VALUES ('stnduser','stnduser',1);
Query OK, 1 row affected (0.001 sec)

ProxySQL Admin> LOAD MYSQL USERS TO RUNTIME;
Query OK, 0 rows affected (0.001 sec)

ProxySQL Admin> SAVE MYSQL USERS TO DISK;
Query OK, 0 rows affected (0.016 sec)
```

You can now connect to ProxySQL as your created user on its client port `6033`. Once connected, make a new write:

```bash
proxysql_example % mysql --host 0.0.0.0 --port 6033 -ustnduser -pstnduser
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 2
Server version: 8.0.11 (ProxySQL)

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
+------------------------------------+
1 row in set (0.02 sec)

mysql> create table t2 (pk int primary key);
Query OK, 0 rows affected (0.04 sec)
```

Verify that both your `primary` and `replica-1` contain the write:

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3307 -uroot -proot        
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 460
Server version: 8.0.42 MySQL Community Server - GPL

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
| t2                                 |
+------------------------------------+
2 rows in set (0.01 sec)
```

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3308 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 504
Server version: 8.0.42 MySQL Community Server - GPL

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
| t2                                 |
+------------------------------------+
2 rows in set (0.01 sec)
```

## Dolt

This example uses [DoltHub](https://www.dolthub.com) as the remote for Dolt's remote replication. To start, ensure you have local Dolt
credentials by running `dolt creds new` and `dolt creds use` commands. This will generate new credentials you can use to make writes to remote databases hosted on DoltHub.

```bash
proxysql_example % dolt creds new
Credentials created successfully.
pub key: omttg68tuuruf3f6ebclkgu5t35vu0ghktt776o6ia3utghrp87g
dolt creds use omttg68tuuruf3f6ebclkgu5t35vu0ghktt776o6ia3utghrp87g
```

Next, be sure to create a database on DoltHub that will be used as the remote. For this example we will use [coffeegodd/read_replication_example](https://www.dolthub.com/repositories/coffeegoddd/read_replication_example), but you will need
to use your own DoltHub database on which you have the permission to make writes. Because this example also relies on cloning the remote database to the Dolt servers running in Docker Compose, you will need to ensure the DoltHub database you create has be initialized
and is not completely empty. We will do this step after making sure we have write perms on this database.

To enable your locally generated Dolt creds to push to the DoltHub database you just created, navigate on DoltHub to Profile > Settings > Credentials. Enter the public key of the credentials into the form along with a description and click Add.

Now let's initialize the database. Locally run the following commands:

```bash
mkdir read_replication_example
cd read_replication_example
dolt init
dolt remote add origin coffeegoddd/read_replication_example
dolt push origin main
```

```bash
proxysql_example % mkdir read_replication_example
proxysql_example % cd read_replication_example 
read_replication_example % dolt init
dolt remote add origin coffeegoddd/read_replication_example
dolt push origin main
Successfully initialized dolt data repository.
\ Uploading...
To https://doltremoteapi.dolthub.com/coffeegoddd/read_replication_example
 * [new branch]          main -> main
```

You can now remove this local copy of the database, as the remote contains the necessary data.

```bash
cd ../
rm -rf read_replication_example
```

Next, edit the ./dolt-docker-compose.yaml file so that the local path to your Dolt creds folder is correct. These are normally found at `$HOME/.dolt/creds`:

```yaml
   volumes:
     - /abs/path/to/.dolt/creds:/root/.dolt/creds # replace with the real path to your local $HOME/.dolt/creds
```

For this example, for me, this will be:

```yaml
   volumes:
     - /Users/dustin/.dolt/creds:/root/.dolt/creds # replace with the real path to your local $HOME/.dolt/creds
```

Save these edits.

Next, start ProxySQL with a simple Dolt read replica cluster using Docker Compose by running the following command:

```bash
DOLT_CREDS_PUBLIC_KEY=omttg68tuuruf3f6ebclkgu5t35vu0ghktt776o6ia3utghrp87g docker compose -f dolt-docker-compose.yaml up
```

This will start three containers in Docker, `primary`, `replica-1`, and `proxysql`. Once the servers come up, you will need to
configure replication between `primary` and `replica-1`. It is import to note that in the case of Dolt replication, the `monitor` user the ProxySQL uses
to monitor the health of the servers must be created on both the `primary` and `replica-1` servers. This has been done already during server initialization, by the
`./primary-init-db.sh` and `./replica-1-init-db.sh` scripts respectively.

Once the servers come online, verify that `primary` and `replica-1` are successfully replicating. Connect to `primary` and execute a write, followed by a Dolt commit:

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3307 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 2
Server version: 8.0.33 Dolt

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Database changed
mysql> create table t1 (pk int primary key);
Query OK, 0 rows affected (0.00 sec)

mysql> call dolt_commit('-Am', 'create table t1');
+----------------------------------+
| hash                             |
+----------------------------------+
| gvj1a2vns3c8k6rqon476gjepngv804j |
+----------------------------------+
1 row in set (2.25 sec)
```

Then, you should see this write reflected on both the DoltHub database, and in `replica-1`.

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3308 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 2
Server version: 8.0.33 Dolt

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
+------------------------------------+
1 row in set (0.23 sec)
```

Now that replication is working, it's time to configure ProxySQL to monitor and route to the Dolt servers.

Because this is running in Docker, and ProxySQL requires the admin to connect on the same host its running on, use `docker exec` to shell into the running `proxysql` container:

```bash
proxysql_example % docker ps
CONTAINER ID   IMAGE                            COMMAND                  CREATED         STATUS         PORTS                               NAMES
7e64122c92f8   proxysql/proxysql:latest         "proxysql --initial …"   2 minutes ago   Up 2 minutes   0.0.0.0:6032-6033->6032-6033/tcp    proxysql
3f1ca186cf64   dolthub/dolt-sql-server:latest   "tini -- docker-entr…"   2 minutes ago   Up 2 minutes   33060/tcp, 0.0.0.0:3308->3306/tcp   replica-1
2a23add7dac9   dolthub/dolt-sql-server:latest   "tini -- docker-entr…"   2 minutes ago   Up 2 minutes   33060/tcp, 0.0.0.0:3307->3306/tcp   primary
proxysql_example % docker exec -it 7e64122c92f8 /bin/bash
root@7e64122c92f8:/#
```

Now, following the [configuration docs from ProxySQL](https://proxysql.com/documentation/proxysql-configuration/), connect to the admin port and enable monitoring by running the following SQL:

```sql
UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_username';
UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_password';
UPDATE global_variables SET variable_value='2000' WHERE variable_name IN ('mysql-monitor_connect_interval','mysql-monitor_ping_interval','mysql-monitor_read_only_interval');
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
LOAD MYSQL SERVERS TO RUNTIME;
```

```bash
root@7e64122c92f8:/# mysql -u admin -padmin -h 127.0.0.1 -P6032 --prompt 'ProxySQL Admin> '
Welcome to the MariaDB monitor.  Commands end with ; or \g.
Your MySQL connection id is 1
Server version: 8.0.11 (ProxySQL Admin Module)

Copyright (c) 2000, 2018, Oracle, MariaDB Corporation Ab and others.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

ProxySQL Admin> UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_username';
Query OK, 1 row affected (0.003 sec)

ProxySQL Admin> UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_password';
Query OK, 1 row affected (0.002 sec)

ProxySQL Admin> UPDATE global_variables SET variable_value='2000' WHERE variable_name IN ('mysql-monitor_connect_interval','mysql-monitor_ping_interval','mysql-monitor_read_only_interval');
Query OK, 3 rows affected (0.002 sec)

ProxySQL Admin> LOAD MYSQL VARIABLES TO RUNTIME;
Query OK, 0 rows affected (0.003 sec)

ProxySQL Admin> SAVE MYSQL VARIABLES TO DISK;
Query OK, 167 rows affected (0.006 sec)

ProxySQL Admin> LOAD MYSQL SERVERS TO RUNTIME;
Query OK, 0 rows affected (0.002 sec)
```

Next, check that the backend servers are healthy:

```bash
ProxySQL Admin> SELECT * FROM mysql_servers;
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname  | port | gtid_port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 10           | primary   | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
| 20           | replica-1 | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
2 rows in set (0.001 sec)

ProxySQL Admin> SHOW TABLES FROM monitor;
+--------------------------------------+
| tables                               |
+--------------------------------------+
| mysql_server_aws_aurora_check_status |
| mysql_server_aws_aurora_failovers    |
| mysql_server_aws_aurora_log          |
| mysql_server_connect_log             |
| mysql_server_galera_log              |
| mysql_server_group_replication_log   |
| mysql_server_ping_log                |
| mysql_server_read_only_log           |
| mysql_server_replication_lag_log     |
+--------------------------------------+
9 rows in set (0.001 sec)

ProxySQL Admin> SELECT * FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 3;
+-----------+------+------------------+-------------------------+---------------+
| hostname  | port | time_start_us    | connect_success_time_us | connect_error |
+-----------+------+------------------+-------------------------+---------------+
| replica-1 | 3306 | 1744920205884452 | 1371                    | NULL          |
| primary   | 3306 | 1744920205854288 | 2896                    | NULL          |
| replica-1 | 3306 | 1744920203888731 | 7385                    | NULL          |
+-----------+------+------------------+-------------------------+---------------+
3 rows in set (0.001 sec)

ProxySQL Admin> SELECT * FROM monitor.mysql_server_ping_log ORDER BY time_start_us DESC LIMIT 3;
+-----------+------+------------------+----------------------+------------+
| hostname  | port | time_start_us    | ping_success_time_us | ping_error |
+-----------+------+------------------+----------------------+------------+
| replica-1 | 3306 | 1744920211964675 | 584                  | NULL       |
| primary   | 3306 | 1744920211964304 | 906                  | NULL       |
| replica-1 | 3306 | 1744920209963009 | 517                  | NULL       |
+-----------+------+------------------+----------------------+------------+
3 rows in set (0.001 sec)
```

Next, run the following `INSERT` to configure the replication hostgroups in ProxySQL:

```sql
INSERT INTO mysql_replication_hostgroups (writer_hostgroup,reader_hostgroup,comment) VALUES (10,20,'cluster1');
LOAD MYSQL SERVERS TO RUNTIME;
```

```bash
ProxySQL Admin> INSERT INTO mysql_replication_hostgroups (writer_hostgroup,reader_hostgroup,comment) VALUES (10,20,'cluster1');
Query OK, 1 row affected (0.001 sec)

ProxySQL Admin> LOAD MYSQL SERVERS TO RUNTIME;
Query OK, 0 rows affected (0.006 sec)
```

And verify the read-only configuration of your backends before persisting the changes to disk:

```bash
ProxySQL Admin> SELECT * FROM monitor.mysql_server_read_only_log ORDER BY time_start_us DESC LIMIT 3;
+-----------+------+------------------+-----------------+-----------+-------+
| hostname  | port | time_start_us    | success_time_us | read_only | error |
+-----------+------+------------------+-----------------+-----------+-------+
| primary   | 3306 | 1744920300184814 | 1890            | 0         | NULL  |
| replica-1 | 3306 | 1744920299975185 | 211603          | 0         | NULL  |
| primary   | 3306 | 1744920298179238 | 2364            | 0         | NULL  |
+-----------+------+------------------+-----------------+-----------+-------+
3 rows in set (0.002 sec)

ProxySQL Admin> SELECT * FROM mysql_servers;
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname  | port | gtid_port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 10           | primary   | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
| 20           | replica-1 | 3306 | 0         | ONLINE | 1      | 0           | 100             | 0                   | 0       | 0              |         |
+--------------+-----------+------+-----------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
2 rows in set (0.001 sec)

ProxySQL Admin> SAVE MYSQL SERVERS TO DISK;
Query OK, 0 rows affected (0.032 sec)

ProxySQL Admin> SAVE MYSQL VARIABLES TO DISK;
Query OK, 167 rows affected (0.011 sec)
```

Finally, your cluster should be working properly, and you can begin adding credentials for end users of your service.

To do so, connect to the primary and run the following SQL to create a sample user:

```sql
CREATE USER 'stnduser'@'%' IDENTIFIED BY 'stnduser';
GRANT ALL PRIVILEGES ON *.* TO 'stnduser'@'%';
```

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3307 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 106
Server version: 8.0.33 Dolt

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> CREATE USER 'stnduser'@'%' IDENTIFIED BY 'stnduser';
Query OK, 0 rows affected (0.01 sec)

mysql> GRANT ALL PRIVILEGES ON *.* TO 'stnduser'@'%';
Query OK, 0 rows affected (0.01 sec)
```

Then return to the ProxySQL admin shell, and run the following SQL to register this user:

```sql
INSERT INTO mysql_users(username,password,default_hostgroup) VALUES ('stnduser','stnduser',1);
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
```

```bash
ProxySQL Admin> INSERT INTO mysql_users(username,password,default_hostgroup) VALUES ('stnduser','stnduser',1);
Query OK, 1 row affected (0.004 sec)

ProxySQL Admin> LOAD MYSQL USERS TO RUNTIME;
Query OK, 0 rows affected (0.001 sec)

ProxySQL Admin> SAVE MYSQL USERS TO DISK;
Query OK, 0 rows affected (0.012 sec)
```

You can now connect to ProxySQL as your created user on its client port `6033`. Once connected, make a new write:

```bash
proxysql_example % mysql --host 0.0.0.0 --port 6033 -ustnduser -pstnduser
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 2
Server version: 8.0.11 (ProxySQL)

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
+------------------------------------+
1 row in set (0.01 sec)

mysql> create table t2 (pk int primary key);
Query OK, 0 rows affected (0.01 sec)

mysql> call dolt_commit('-Am', 'create table t2');
+----------------------------------+
| hash                             |
+----------------------------------+
| 4mmjaev3vbeh5m8cqp3mehlt4jcsivlv |
+----------------------------------+
1 row in set (1.95 sec)
```

Verify that both your `primary` and `replica-1` contain the write:

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3307 -uroot -proot        
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 176
Server version: 8.0.33 Dolt

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
| t2                                 |
+------------------------------------+
2 rows in set (0.00 sec)
```

```bash
proxysql_example % mysql --host 0.0.0.0 --port 3308 -uroot -proot
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 203
Server version: 8.0.33 Dolt

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use read_replication_example;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+------------------------------------+
| Tables_in_read_replication_example |
+------------------------------------+
| t1                                 |
| t2                                 |
+------------------------------------+
2 rows in set (0.23 sec)
```

You should also see the write on your DoltHub remote database.
