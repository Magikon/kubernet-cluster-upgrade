# Cluster Operations

This project will help to create a new cluster, delete, update an existing cluster.



### Usage

Update master and nodes to default version
```shell
./kub.sh update
```

Update master and nodes to latest version
```shell
./kub.sh update latest
```

Creates pools DEFAULT, FAST, REVIEW. If the cluster name does not exist in the project,
creates a new cluster and, if ip1, ip2, ip3 are missing, it will create 3 IP, 
as well as IP for the balancer, and prints them after the script.
```shell
./kub.sh create
```

Remove pools from existing cluster with confirmation for each pool.
```shell
./kub.sh delete
```

To remove all polls of cluster without confirmation.
```shell
./kub.sh delete all
```



For each client we need to create config file `/config/user-cluster.yml`.

```yaml
include:
    - local: /config/test-com.yml
```


### Exported Variables


| Variable Names            | Description                                               |
|:--------------------------|:----------------------------------------------------------|
| CLUSTERNAME               | New or existing cluster name                              |
| ZONEVAR                   | Zone of cluster                                           |
| REGIONVAR                 | Region of cluster                                         |
| IP1                       | Whitelisted IP addresses,                                 |
| IP2                       | if omitted - script create new ip addresses for new,      |
| IP3                       | cluster and print it after work                           |
| DISKSIZE                  | Node disk size (default is 100GB)                         |
| DISKTYPE                  | Node disk type (default is  pd-standard)                  |
| DEF_MACHINETYPE           | Default Pool machine type                                 |
| DEF_MINNODECOUNT          | Default Pool minimal node count                           |
| DEF_MAXNODECOUNT          | Default Pool maximal node count                           |
| DEF_INITIALNODECOUNT      | Default Pool number of nodes                              |
| FST_MACHINETYPE           | Fast Pool machine type                                    |
| FST_MINNODECOUNT          | Fast Pool minimal node count                              |
| FST_MAXNODECOUNT          | Fast Pool maximal node count                              |
| FST_INITIALNODECOUNT      | Fast Pool number of nodes                                 |
| REV_MACHINETYPE           | Review Pool machine type                                  |
| REV_MINNODECOUNT          | Review Pool minimal node count                            |
| REV_MAXNODECOUNT          | Review Pool maximal node count                            |
| REV_INITIALNODECOUNT      | Review Pool number of nodes                               |


