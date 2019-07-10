#!/usr/bin/env bash
# The script can create pools of nodes, delete all pools of nodes or selectively, update pools of nodes by default or to the latest version.
set -e
#set -x
start=`date +%s`
#printenv

nodePool1="default-pool"
nodePool2="fast-pool"
nodePool3="review-pool"

# CLUSTERNAME="${CLUSTERVAR:-inplay-io}"
# ZONEVAR="${ZONEVAR:-europe-west3-a}"
# REGIONVAR="${REGIONVAR:-europe-west3}"

# IP1="${IP1:-35.198.145.44}"
# IP2="${IP2:-35.198.175.55}"
# IP3="${IP3:-35.198.128.216}"

# DISKSIZE="100GB"
# DISKTYPE="pd-standard"

# # create node pool default
# DEF_MACHINETYPE="n1-standard-4"
# DEF_MINNODECOUNT="4"
# DEF_MAXNODECOUNT="8"
# DEF_INITIALNODECOUNT="4"
# # create node pool fast
# FST_MACHINETYPE="n1-highcpu-4"
# FST_MINNODECOUNT="1"
# FST_MAXNODECOUNT="1"
# FST_INITIALNODECOUNT="1"
# # create node pool review
# REV_MACHINETYPE="n1-standard-1"
# REV_MINNODECOUNT="1"
# REV_MAXNODECOUNT="3"
# REV_INITIALNODECOUNT="3"

#for multiline use ; as delimiter
echos()
{
    local str="$@"
    echo "-- "
    IFS=\; read -a arr <<<"$str"
    for i in "${arr[@]}";do
        echo "-- ""$i"
    done
    echo "-- " 
}

helps()
{
    echos "Usage - "$0" update|create|delete;  ex. - "$0" update latest (update to default version use without 2nd arg);\
  ex. - "$0" delete all (for selective deleteion use without 2nd arg);  ex. - "$0" create"
}

crNodePool()
{
    echos "Create new pool - " "$1"
    echo "--quiet container node-pools create "$1" --cluster="$CLUSTERNAME" --zone="$ZONEVAR" --enable-autorepair --enable-autoscaling \
    --machine-type="$2" --num-nodes="$3" --min-nodes="$4" --max-nodes="$5" --disk-type="pd-standard" \
    "$6" --no-enable-autoupgrade --metadata=disable-legacy-endpoints=true" | xargs -t gcloud
}

setIP()
{
    local ipAddress="$1"
    local nodeName="$2"
    local tempnode=`gcloud compute instances list | awk '/'$ipAddress'/ {print $1}'`
    if [ ! -z "$tempnode" ];
    then 
        echos "Remove " "$ipAddress" " from " "$tempnode"
        local exNat=`gcloud compute instances describe "$tempnode" --zone="$ZONEVAR" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`
        gcloud --quiet compute instances delete-access-config "$tempnode" --access-config-name="$exNat" --zone="$ZONEVAR";
        gcloud --quiet compute instances add-access-config "$tempnode" --access-config-name="$exNat" --zone="$ZONEVAR";
    fi
    echos "Set " "$ipAddress" " to " "$nodeName"
    exNat=`gcloud compute instances describe "$nodeName" --zone="$ZONEVAR" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`
    gcloud --quiet compute instances delete-access-config "$nodeName" --access-config-name="$exNat" --zone="$ZONEVAR"
    gcloud --quiet compute instances add-access-config "$nodeName" --access-config-name="$exNat" --address "$ipAddress" --zone="$ZONEVAR"
}

drain()
{
    echos "Cordon old pools"
    for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$1" -o=name); do
        kubectl cordon "$node";
    done
    
    echos "Drain old pools"
    for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$1" -o=name); do
        kubectl drain --force --ignore-daemonsets --delete-local-data --grace-period=45 "$node";
    sleep 30s
    done
}

#==================================================================================================================================
update()
{
    mainVersion=`gcloud container get-server-config --zone="$ZONEVAR" | awk '/validMasterVersions/ { getline; print $NF }'`
    defaultVersion=`gcloud container get-server-config --zone="$ZONEVAR" | awk '/defaultClusterVersion/ { print $NF }'`
    if [ "$1" == "latest" ]
    then
        echos "Convert to version " "$mainVersion"
        gcloud --quiet container clusters upgrade "$CLUSTERNAME" --master --cluster-version "$mainVersion" --zone="$ZONEVAR"
    else
        echos "Convert to version " "$defaultVersion"
        gcloud --quiet container clusters upgrade "$CLUSTERNAME" --master --zone="$ZONEVAR"
    fi

    echos "Change names with opposite names and saves old names"
    while IFS= read -r line
    do
        case $line in
        *defaultpool*)
            nodePool1="default-pool";oldpool1="$line" ;;
        *default-pool*)
            nodePool1="defaultpool";oldpool1="$line" ;;
        *fastpool*)
            nodePool2="fast-pool";oldpool2="$line" ;;
        *fast-pool*)
            nodePool2="fastpool";oldpool2="$line" ;;
            *reviewpool*)
        nodePool3="review-pool";oldpool3="$line" ;;
            *review-pool*)
        nodePool3="reviewpool";oldpool3="$line" ;;
        esac
    done < <(gcloud --quiet container node-pools list --cluster="$CLUSTERNAME" --zone="$ZONEVAR" | awk '{if (NR!=1) {print $1}}')

    echos "Old names of pools is" "$oldpool1" "$oldpool2" "$oldpool3" "-" "New names of pools is" "$nodePool1" "$nodePool2" "$nodePool3"
#------------------------------------------------------------------------------------------------------------------------
    while IFS= read -r line
    do
        case $line in
        *machineType*)
            machineType=$(awk '{ print $NF }' <<< "$line") ;;
        *maxNodeCount*)
            maxNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
        *minNodeCount*)
            minNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
        esac
    done < <(gcloud container node-pools describe --cluster="$CLUSTERNAME" --zone="$ZONEVAR" "$oldpool1")

    initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool1" -o=name | wc -l)

    crNodePool "$nodePool1" "$machineType" "$initialNodeCount" "$minNodeCount" "$maxNodeCount"

    echos "Save node's names of new pool"
    count=1
    for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$nodePool1" -o=name); do
        export nodes${count}=${node#*/}
        echos "$count" "-" "${node#*/}"
        let count+=1
    done

    echos "Set labels for node1=" "$nodes1"
    kubectl label nodes "$nodes1" whitelist=betradar

    setIP "$IP1" "$nodes1"

    drain "$oldpool1"

    echos "Set labels for node1=" "$nodes2"
    kubectl label nodes "$nodes2" whitelist=betradar

    setIP "$IP2" "$nodes2"

#------------------------------------------------------------------------------------------------------------------------
    while IFS= read -r line
    do
        case $line in
        *machineType*)
            machineType=$(awk '{ print $NF }' <<< "$line") ;;
        *maxNodeCount*)
            maxNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
        *minNodeCount*)
            minNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
        esac
    done < <(gcloud container node-pools describe --cluster="$CLUSTERNAME" "$oldpool2")

    initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool2" -o=name | wc -l)

    crNodePool "$nodePool2" "$machineType" "$initialNodeCount" "$minNodeCount" "$maxNodeCount" "--node-labels=whitelist=betradar,nodetype=fast --node-taints=fast_node=only:NoSchedule"

    echos "Save node's names of new pool"
    count=1
    for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$nodePool2" -o=name); do
        export nodes${count}=${node#*/}
        echos "$count" "-" "${node#*/}"
        let count+=1
    done

    setIP "$IP3" "$nodes1"

    drain "$oldpool2"

#------------------------------------------------------------------------------------------------------------------------
    while IFS= read -r line
    do
        case $line in
        *machineType*)
            machineType=$(awk '{ print $NF }' <<< "$line") ;;
        *maxNodeCount*)
            maxNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
        *minNodeCount*)
            minNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
        esac
    done < <(gcloud container node-pools describe --cluster="$CLUSTERNAME" "$oldpool3")

    initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool3" -o=name | wc -l)

    crNodePool "$nodePool3" "$machineType" "$initialNodeCount" "$minNodeCount" "$maxNodeCount" "--node-labels=nodetype=review --node-taints=review_node=only:NoSchedule --preemptible"

    drain "$oldpool3"

#------------------------------------------------------------------------------------------------------------------------

    echos "Delete old pool " "$oldpool1"
    gcloud --quiet container node-pools delete "$oldpool1" --cluster="$CLUSTERNAME" --zone="$ZONEVAR"

    echos "Delete old pool " "$oldpool2"
    gcloud --quiet container node-pools delete "$oldpool2" --cluster="$CLUSTERNAME" --zone="$ZONEVAR"

    echos "Delete old pool " "$oldpool3"
    gcloud --quiet container node-pools delete "$oldpool3" --cluster="$CLUSTERNAME" --zone="$ZONEVAR"

}
#==================================================================================================================================
createCluster()
{
    gcloud container clusters create "$CLUSTERNAME" --zone="$ZONEVAR" --num-nodes=1 --enable-autorepair --machine-type="g1-small" --preemptible --enable-basic-auth
    gcloud config set compute/zone "$ZONEVAR"
    gcloud config set container/cluster "$CLUSTERNAME";
    gcloud container clusters get-credentials "$CLUSTERNAME" --zone "$ZONEVAR" --project "$INPLAY_PROJECT"
    #kubectl config view
    #kubectl get nodes
    delete all
    echos "Creating new IP's for this cluster"
    if [ -z $IP1 ] || [ -z $IP2 ] || [ -z $IP3 ]; then
        gcloud --quiet compute addresses create "$CLUSTERNAME-balancer" "$CLUSTERNAME-ip1" "$CLUSTERNAME-ip2" "$CLUSTERNAME-ip3" --region "$REGIONVAR";
        IP1=`gcloud compute addresses list | awk '/'$CLUSTERNAME-ip1'/ {print $2}'`;
        IP2=`gcloud compute addresses list | awk '/'$CLUSTERNAME-ip2'/ {print $2}'`;
        IP3=`gcloud compute addresses list | awk '/'$CLUSTERNAME-ip3'/ {print $2}'`;
        IPB=`gcloud compute addresses list | awk '/'$CLUSTERNAME-balancer'/ {print $2}'`;
        swichecho=true
    fi
}
#==================================================================================================================================
create()
{
    crNodePool "$nodePool1" "$DEF_MACHINETYPE" "$DEF_INITIALNODECOUNT" "$DEF_MINNODECOUNT" "$DEF_MAXNODECOUNT"

    echos "Save node's names of new pool"
    count=1
    for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$nodePool1" -o=name); do
        export nodes${count}=${node#*/}
        echos "$count" "-" "${node#*/}"
        let count+=1
    done

    echos "Set labels for node1=" "$nodes1"
    kubectl label nodes "$nodes1" whitelist=betradar

    echos "Set labels for node2=" "$nodes2"
    kubectl label nodes "$nodes2" whitelist=betradar

    setIP "$IP1" "$nodes1"

    setIP "$IP2" "$nodes2"

#------------------------------------------------------------------------------------------------------------------------
    crNodePool "$nodePool2" "$FST_MACHINETYPE" "$FST_INITIALNODECOUNT" "$FST_MINNODECOUNT" "$FST_MAXNODECOUNT" "--node-labels=whitelist=betradar,nodetype=fast --node-taints=fast_node=only:NoSchedule"

    echos "Save node's names of new pool"
    count=1
    for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$nodePool2" -o=name); do
        export nodes${count}=${node#*/}
        echos "$count" "-" "${node#*/}"
        let count+=1
    done

    setIP "$IP3" "$nodes1"

#------------------------------------------------------------------------------------------------------------------------
    crNodePool "$nodePool3" "$REV_MACHINETYPE" "$REV_INITIALNODECOUNT" "$REV_MINNODECOUNT" "$REV_MAXNODECOUNT" "--node-labels=nodetype=review --node-taints=review_node=only:NoSchedule --preemptible"
}
#==================================================================================================================================
delete()
{
    while IFS= read -r line <&3
    do
        if [ "$1" == "all" ]
        then 
            gcloud --quiet container node-pools delete --zone="$ZONEVAR" --cluster="$CLUSTERNAME" "$line"
        else
            promts="Delete pool ""$line"" (y/n)?"
            read -n 1 -r -p "$promts" zz
            echo
            if [[ $zz =~ ^[Yy]$ ]]
            then
                gcloud --quiet container node-pools delete --zone="$ZONEVAR" --cluster="$CLUSTERNAME" "$line"
            fi
        fi
    done 3< <(gcloud --quiet container node-pools list --zone="$ZONEVAR" --cluster="$CLUSTERNAME" | awk '{if (NR!=1) {print $1}}')
}
#==================================================================================================================================

if [[ $# -le 0 ]];then helps;fi

key="$1"

readarray arr < <(gcloud container clusters list --format="value(name)")
if [[ "${arr[*]}" =~ "$CLUSTERNAME" ]];
then
    gcloud config set compute/zone "$ZONEVAR"
    gcloud config set container/cluster "$CLUSTERNAME";
    gcloud container clusters get-credentials "$CLUSTERNAME" --zone "$ZONEVAR" --project "$INPLAY_PROJECT"
    #kubectl config view
    #kubectl get nodes
else
    if [ "$key" == "create" ];then createCluster;fi
fi



case $key in
    -u|--u|update|-update|--update)
        if [ "$2" == "latest" ] || [ "$2" == "default" ];then ext="$2";shift;fi
        update "$ext"
        shift
    ;;
    -d|--d|delete|-delete|--delete)
        if [ "$2" == "all" ];then ext="$2";shift;fi
        delete "$ext"
        shift
    ;;
    -c|--c|create|-create|--create)
        create
        shift
    ;;
    -cc|--cc|createcluster|-createcluster|--createcluster)
        createCluster
        shift
    ;;
    -h|--h|help|-help|--help)
        helps
        shift
    ;;
    *)
        echos "Unknown parameter"
        helps
    ;;
esac

end=`date +%s`

echos "From the beginning of the script has passed" $((end-start))s

if [ $swichecho ];then echos "IP1:      $IP1;IP2:      $IP2;IP3:      $IP3;Balanser: $IPB";fi