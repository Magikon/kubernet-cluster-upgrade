#!/usr/bin/env bash
# The script can create pools of nodes, delete all pools of nodes or selectively, update pools of nodes by default or to the latest version.
set -e
set -x
start=`date +%s`

clusterName="cluster1"
zone="us-central1-a"
region="us-central1"

nodePool1="default-pool"
nodePool2="fast-pool"
nodePool3="review-pool"

IP1="35.192.124.25"
IP2="35.192.124.25"
IP3="35.192.124.25"

disksize="100GB"
diskType="pd-standard"

#create node pool default
def_machineType="g1-small"
def_minNodeCount="1"
def_maxNodeCount="2"
def_initialNodeCount="2"
#create node pool fast
fst_machineType="g1-small"
fst_minNodeCount="1"
fst_maxNodeCount="1"
fst_initialNodeCount="1"
#create node pool review
rev_machineType="g1-small"
rev_minNodeCount="1"
rev_maxNodeCount="1"
rev_initialNodeCount="1"

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
  exit 1
}

crNodePool()
{
  echos "Create new pool - " "$1"
  echo "--quiet container node-pools create "$1" --cluster="$clusterName" --zone="$zone" --enable-autorepair --enable-autoscaling \
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
     local exNat=`gcloud compute instances describe "$tempnode" --zone="$zone" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`
     gcloud --quiet compute instances delete-access-config "$tempnode" --access-config-name="$exNat" --zone="$zone";
     gcloud --quiet compute instances add-access-config "$tempnode" --access-config-name="$exNat" --zone="$zone";
  fi

  echos "Set " "$ipAddress" " to " "$nodeName"
  exNat=`gcloud compute instances describe "$nodeName" --zone="$zone" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`
  gcloud --quiet compute instances delete-access-config "$nodeName" --access-config-name="$exNat" --zone="$zone"
  gcloud --quiet compute instances add-access-config "$nodeName" --access-config-name="$exNat" --address "$ipAddress" --zone="$zone"
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
    sleep 20s
  done
}

#==================================================================================================================================
update()
{
mainVersion=`gcloud container get-server-config --zone="$zone" | awk '/validMasterVersions/ { getline; print $NF }'`
defaultVersion=`gcloud container get-server-config --zone="$zone" | awk '/defaultClusterVersion/ { print $NF }'`
if [ "$1" == "latest" ]
then
  echos "Convert to version " "$mainVersion"
  gcloud --quiet container clusters upgrade "$clusterName" --master --cluster-version "$mainVersion" --zone="$zone"
else
  echos "Convert to version " "$defaultVersion"
  gcloud --quiet container clusters upgrade "$clusterName" --master --zone="$zone"
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
done < <(gcloud --quiet container node-pools list --cluster="$clusterName" --zone="$zone" | awk '{if (NR!=1) {print $1}}')

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
done < <(gcloud container node-pools describe --cluster="$clusterName" --zone="$zone" "$oldpool1")

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
done < <(gcloud container node-pools describe --cluster="$clusterName" "$oldpool2")

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
done < <(gcloud container node-pools describe --cluster="$clusterName" "$oldpool3")

initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool3" -o=name | wc -l)

crNodePool "$nodePool3" "$machineType" "$initialNodeCount" "$minNodeCount" "$maxNodeCount" "--node-labels=nodetype=review --node-taints=review_node=only:NoSchedule --preemptible"

drain "$oldpool3"

#------------------------------------------------------------------------------------------------------------------------

echos "Delete old pool " "$oldpool1"
gcloud --quiet container node-pools delete "$oldpool1" --cluster="$clusterName" --zone="$zone"

echos "Delete old pool " "$oldpool2"
gcloud --quiet container node-pools delete "$oldpool2" --cluster="$clusterName" --zone="$zone"

echos "Delete old pool " "$oldpool3"
gcloud --quiet container node-pools delete "$oldpool3" --cluster="$clusterName" --zone="$zone"

}
#==================================================================================================================================
create()
{
crNodePool "$nodePool1" "$def_machineType" "$def_initialNodeCount" "$def_minNodeCount" "$def_maxNodeCount"

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
crNodePool "$nodePool2" "$fst_machineType" "$fst_initialNodeCount" "$fst_minNodeCount" "$fst_maxNodeCount" "--node-labels=whitelist=betradar,nodetype=fast --node-taints=fast_node=only:NoSchedule"

echos "Save node's names of new pool"
count=1
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$nodePool2" -o=name); do
    export nodes${count}=${node#*/}
    echos "$count" "-" "${node#*/}"
    let count+=1
done

setIP "$IP3" "$nodes1"

#------------------------------------------------------------------------------------------------------------------------
crNodePool "$nodePool3" "$rev_machineType" "$rev_initialNodeCount" "$rev_minNodeCount" "$rev_maxNodeCount" "--node-labels=nodetype=review --node-taints=review_node=only:NoSchedule --preemptible"
}
#==================================================================================================================================
delete()
{
while IFS= read -r line <&3
do
   if [ "$1" == "all" ]
   then 
     gcloud --quiet container node-pools delete --zone="$zone" --cluster="$clusterName" "$line"
   else
     promts="Delete pool ""$line"" (y/n)?"
     read -n 1 -r -p "$promts" zz
	 echo
	 if [[ $zz =~ ^[Yy]$ ]]
	 then
	   gcloud --quiet container node-pools delete --zone="$zone" --cluster=$clusterName "$line"
	 fi
   fi
done 3< <(gcloud --quiet container node-pools list --zone="$zone" --cluster=$clusterName | awk '{if (NR!=1) {print $1}}')
}
#==================================================================================================================================

if [[ $# -le 0 ]];then helps;fi

key="$1"

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
