#!/usr/bin/env bash
set -e
start=`date +%s`

clusterName="cluster1"
zone="us-central1-a"
region="us-central1"
disksize="100GB"
diskType="pd-standard"
IP1="35.192.124.25"
IP2="35.192.124.26"
IP3="35.192.124.27"

echo "-- Select the newest version and update the master of this version:
--"
# find in get-server-config last valid version of master(awk get line after "validMasterVersions" and print last field)
mainVersion=`gcloud container get-server-config | awk '/validMasterVersions/ { getline; print $NF }'`
echo "-- convert to version " $mainVersion
gcloud --quiet container clusters upgrade "$clusterName" --master --cluster-version "$mainVersion"

echo "-- Change names with opposite names and saves old names
--"
while IFS= read -r line
do
  case $line in
    *defaultpool*)
      pool1="default-pool";oldpool1="$line" ;;
    *default-pool*)
      pool1="defaultpool";oldpool1="$line" ;;
    *fastpool*)
      pool2="fast-pool";oldpool2="$line" ;;
    *fast-pool*)
      pool2="fastpool";oldpool2="$line" ;;
    *reviewpool*)
      pool3="review-pool";oldpool3="$line" ;;
    *review-pool*)
      pool3="reviewpool";oldpool3="$line" ;;
  esac
done < <(gcloud --quiet container node-pools list --cluster="$clusterName" | awk '{if (NR!=1) {print $1}}')

echo "-- Old names of pools is" "$oldpool1" "$oldpool2" "$oldpool3"
echo "-- New names of pools is" "$pool1" "$pool2" "$pool3"
echo "--"
#------------------------------------------------------------------------------------------------------------------------
echo "-- find some params of old default pools
--"
while IFS= read -r line
do
  case $line in
    *diskType*)
      diskType=$(awk '{ print $NF }' <<< "$line") ;;
    *machineType*)
      machineType=$(awk '{ print $NF }' <<< "$line") ;;
    *maxNodeCount*)
      maxNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
    *minNodeCount*)
      minNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
  esac
done < <(gcloud container node-pools describe --cluster="$clusterName" "$oldpool1")

initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool1" -o=name | wc -l)

echo "-- 
-- create the new default pool
--"
echo "gcloud --quiet container node-pools create $pool1 --cluster=$clusterName --disk-type=$diskType --machine-type=$machineType \
--num-nodes=$initialNodeCount --max-nodes=$maxNodeCount --min-nodes=$minNodeCount --disk-size=$disksize --zone=$zone \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade"
echo "--"
gcloud --quiet container node-pools create "$pool1" --cluster="$clusterName" --disk-type="$diskType" --machine-type="$machineType" \
--num-nodes="$initialNodeCount" --max-nodes="$maxNodeCount" --min-nodes="$minNodeCount" --disk-size="$disksize" --zone="$zone" \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade

echo "-- 
-- save node's names of new pool
--"
count=1
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$pool1" -o=name); do
    export nodes${count}=${node#*/}
    echo "-- " "$count" "-" "${node#*/}"
    let count+=1
done

echo "-- 
-- set labels for node1=" "$nodes1"
echo "--"
kubectl label nodes "$nodes1" whitelist=betradar

tempnode=`gcloud compute instances list | awk '/'$IP1'/ {print $1}'`

if [ ! -z "$tempnode" ];
then 
   echo "-- remove " "$IP1" " from " "$tempnode"
   exNat=`gcloud compute instances describe "$tempnode" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`
   gcloud --quiet compute instances delete-access-config "$tempnode" --access-config-name="$exNat";
   gcloud --quiet compute instances add-access-config "$tempnode" --access-config-name="$exNat"; 
   unset exNat
fi
unset tempnode

echo "-- set " "$IP1" " to " "$nodes1"

exNat=`gcloud compute instances describe "$nodes1" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`

gcloud --quiet compute instances delete-access-config "$nodes1" --access-config-name="$exNat"
gcloud --quiet compute instances add-access-config "$nodes1" --access-config-name="$exNat" --address "$IP1"
unset exNat

echo "-- 
-- cordon old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool1 -o=name); do
  kubectl cordon "$node";
done

echo "-- 
-- drain old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool1" -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-local-data --grace-period=45 "$node";
done

echo "-- 
-- set labels for node1=" "$nodes2"
echo "--"
kubectl label nodes "$nodes2" whitelist=betradar

tempnode=`gcloud compute instances list | awk '/'$IP2'/ {print $1}'`

if [ ! -z "$tempnode" ];
then 
   echo "-- remove " "$IP2" " from " "$tempnode"
   exNat=`gcloud compute instances describe "$tempnode" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`   
   gcloud --quiet compute instances delete-access-config "$tempnode" --access-config-name="$exNat";
   gcloud --quiet compute instances add-access-config "$tempnode" --access-config-name="$exNat"; 
   unset exNat
fi
unset tempnode

echo "-- set " "$IP2" " to " "$nodes2"

exNat=`gcloud compute instances describe "$nodes2" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`

gcloud --quiet compute instances delete-access-config "$nodes2" --access-config-name="$exNat"
gcloud --quiet compute instances add-access-config "$nodes2" --access-config-name="$exNat" --address "$IP2"
unset exNat

echo "-- delete old pool " "$oldpool1"
gcloud --quiet container node-pools delete "$oldpool1" --cluster="$clusterName"
#------------------------------------------------------------------------------------------------------------------------
echo "-- find some params of old fast pools
--"
while IFS= read -r line
do
  case $line in
    *diskType*)
      diskType=$(awk '{ print $NF }' <<< "$line") ;;
    *machineType*)
      machineType=$(awk '{ print $NF }' <<< "$line") ;;
    *maxNodeCount*)
      maxNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
    *minNodeCount*)
      minNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
  esac
done < <(gcloud container node-pools describe --cluster="$clusterName" "$oldpool2")

initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool2" -o=name | wc -l)

echo "-- 
-- create new fast pool
--"
echo "gcloud --quiet container node-pools create $pool2 --cluster=$clusterName --disk-type=$diskType --machine-type=$machineType \
--num-nodes=$initialNodeCount --max-nodes=$maxNodeCount --min-nodes=$minNodeCount --disk-size=$disksize --zone=$zone \
--node-labels=whitelist=betradar,nodetype=fast --node-taints=fast_node=only:NoSchedule \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade"
echo "--"
gcloud --quiet container node-pools create "$pool2" --cluster="$clusterName" --disk-type="$diskType" --machine-type="$machineType" \
--num-nodes="$initialNodeCount" --max-nodes="$maxNodeCount" --min-nodes="$minNodeCount" --disk-size="$disksize" --zone="$zone" \
--node-labels=whitelist=betradar,nodetype=fast --node-taints=fast_node=only:NoSchedule \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade

echo "-- 
-- save node's names of new pool
--"
count=1
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$pool2" -o=name); do
    export nodes${count}=${node#*/}
    echo "-- " "$count" "-" "${node#*/}"
    let count+=1
done

tempnode=`gcloud compute instances list | awk '/'$IP3'/ {print $1}'`

if [ ! -z "$tempnode" ];
then 
   echo "-- remove " "$IP3" " from " "$tempnode"
   exNat=`gcloud compute instances describe "$tempnode" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`
   gcloud --quiet compute instances delete-access-config "$tempnode" --access-config-name="$exNat";
   gcloud --quiet compute instances add-access-config "$tempnode" --access-config-name="$exNat"; 
   unset exNat
fi
unset tempnode

echo "-- set " "$IP3" " to " "$nodes1"

exNat=`gcloud compute instances describe "$nodes1" --format='value(networkInterfaces[].accessConfigs[].name.list())' | awk -F "'" '{ print $2 }'`

gcloud --quiet compute instances delete-access-config "$nodes1" --access-config-name="$exNat"
gcloud --quiet compute instances add-access-config "$nodes1" --access-config-name="$exNat" --address "$IP3"

echo "-- 
-- cordon old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool2" -o=name); do
  kubectl cordon "$node";
done

echo "-- 
-- drain old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool2" -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-local-data --grace-period=45 "$node";
done

echo "-- delete old pool " "$oldpool2"
gcloud --quiet container node-pools delete "$oldpool2" --cluster="$clusterName"
#------------------------------------------------------------------------------------------------------------------------
echo "-- find some params of old review pools
--"
while IFS= read -r line
do
  case $line in
    *diskType*)
      diskType=$(awk '{ print $NF }' <<< "$line") ;;
    *machineType*)
      machineType=$(awk '{ print $NF }' <<< "$line") ;;
    *maxNodeCount*)
      maxNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
    *minNodeCount*)
      minNodeCount=$(awk '{ print $NF }' <<< "$line") ;;
  esac
done < <(gcloud container node-pools describe --cluster="$clusterName" "$oldpool3")

initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool3" -o=name | wc -l)

echo "--
-- create review pool
--"
echo "gcloud --quiet container node-pools create $pool3 --cluster=$clusterName --disk-type=$diskType --machine-type=$machineType \
--num-nodes=$initialNodeCount --max-nodes=$maxNodeCount --min-nodes=$minNodeCount --disk-size=$disksize --zone=$zone \
--node-labels=nodetype=review --node-taints=review_node=only:NoSchedule \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade --preemptible"
echo "--"
gcloud --quiet container node-pools create "$pool3" --cluster="$clusterName" --disk-type="$diskType" --machine-type="$machineType" \
--num-nodes="$initialNodeCount" --max-nodes="$maxNodeCount" --min-nodes="$minNodeCount" --disk-size="$disksize" --zone="$zone" \
--node-labels=nodetype=review --node-taints=review_node=only:NoSchedule \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade --preemptible

echo "-- 
-- cordon old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool3" -o=name); do
  kubectl cordon "$node";
done

echo "-- 
-- drain old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool="$oldpool3" -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-local-data --grace-period=45 "$node";
done

#------------------------------------------------------------------------------------------------------------------------
echo "-- delete old pool " "$oldpool3"
gcloud --quiet container node-pools delete "$oldpool3" --cluster="$clusterName"

end=`date +%s`

echo "-- From the beginning of the script has passed" $((end-start))s
