#!/bin/bash

clusterName="cluster1"
zone="us-central1-a"
region="us-central1"
disksize="100GB"
diskType="pd-standard"
IP1="35.192.124.25"
IP2="35.192.124.25"
IP3="35.192.124.25"

echo "-- Select the newest version and update the master of this version:
-- Version upgrade time is almost 5 minutes
--"
mainVersion=`gcloud container get-server-config | awk 'c&&!--c;/validMasterVersions/{c=1}' | sed -n -e 's/^.*- //p'`
#gcloud --quiet container clusters upgrade $clusterName --master --cluster-version $mainVersion

echo "-- Change names with opposite names and saves old names
--"
while IFS= read -r line
do
  case $line in
    *defaultpool*)
      pool1="default-pool";oldpool1=$line ;;
    *default-pool*)
      pool1="defaultpool";oldpool1=$line ;;
    *fastpool*)
      pool2="fast-pool";oldpool2=$line ;;
    *fast-pool*)
      pool2="fastpool";oldpool2=$line ;;
    *reviewpool*)
      pool3="review-pool";oldpool3=$line ;;
    *review-pool*)
      pool3="reviewpool";oldpool3=$line ;;
  esac
done < <(gcloud --quiet container node-pools list --cluster=$clusterName | awk '{if (NR!=1) {print}}' | awk '{print $1}')

echo "-- Old names of pools is" $oldpool1 $oldpool2 $oldpool3
echo "-- New names of pools is" $pool1 $pool2 $pool3
echo "--"
#------------------------------------------------------------------------------------------------------------------------
echo "-- find some params of old default pools
--"
while IFS= read -r line
do
  case $line in
    *diskType*)
      diskType=$(sed -n 's/diskType: //p' <<< $line) ;;
    *machineType*)
      machineType=$(sed -n 's/machineType: //p' <<< $line) ;;
    *maxNodeCount*)
      maxNodeCount=$(sed -n 's/maxNodeCount: //p' <<< $line) ;;
    *minNodeCount*)
      minNodeCount=$(sed -n 's/minNodeCount: //p' <<< $line) ;;
  esac
done < <(gcloud container node-pools describe --cluster=$clusterName $oldpool1)

initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool1 -o=name | wc -l)

echo "-- create the new default pool - creating in about 5 minutes
--"
gcloud --quiet container node-pools create $pool1 --cluster=$clusterName --disk-type=$diskType --machine-type=$machineType \
--num-nodes=$initialNodeCount --max-nodes=$maxNodeCount --min-nodes=$minNodeCount --disk-size=$disksize --zone=$zone \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade

echo "-- save node's names of new pool
--"
count=1
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$pool1 -o=name); do
    export nodes$count=${node#*/}
    let count+=1
done

echo "-- set labels for node1
--"
kubectl label nodes $nodes1 whitelist=betradar

echo "-- find and delete ips from old node
--"
tempnode=`gcloud compute instances list | grep $IP1 | awk '{print $1}'`
if [ ! -z "$tempnode" ];then gcloud --quiet compute instances delete-access-config $tempnode --access-config-name "external-nat";gcloud --quiet compute instances add-access-config $tempnode --access-config-name "external-nat"; fi
unset tempnode

echo "-- change to new"
gcloud --quiet compute instances delete-access-config $nodes1 --access-config-name "external-nat"
gcloud --quiet compute instances add-access-config $nodes1 --access-config-name "external-nat" --address $IP1

echo "--cordon old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool1 -o=name); do
  kubectl cordon "$node";
done

echo "-- drain old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool1 -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-local-data --grace-period=45 "$node";
done

echo "-- label node2
--"
kubectl label nodes $nodes2 whitelist=betradar

echo "-- find and delete ips from old node
--"
tempnode=`gcloud compute instances list | grep $IP2 | awk '{print $1}'`
if [ ! -z "$tempnode" ];then gcloud --quiet compute instances delete-access-config $tempnode --access-config-name "external-nat";gcloud --quiet compute instances add-access-config $tempnode --access-config-name "external-nat"; fi
unset tempnode

echo "-- change to new"
gcloud --quiet compute instances delete-access-config $nodes2 --access-config-name "external-nat"
gcloud --quiet compute instances add-access-config $nodes2 --access-config-name "external-nat" --address $IP2


#------------------------------------------------------------------------------------------------------------------------
echo "-- find some params of old fast pools
--"
while IFS= read -r line
do
  case $line in
    *diskType*)
      diskType=$(sed -n 's/diskType: //p' <<< $line) ;;
    *machineType*)
      machineType=$(sed -n 's/machineType: //p' <<< $line) ;;
    *maxNodeCount*)
      maxNodeCount=$(sed -n 's/maxNodeCount: //p' <<< $line) ;;
    *minNodeCount*)
      minNodeCount=$(sed -n 's/minNodeCount: //p' <<< $line) ;;
  esac
done < <(gcloud container node-pools describe --cluster=$clusterName $oldpool2)

initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool2 -o=name | wc -l)

echo "-- create new fast pool
--"
gcloud --quiet container node-pools create $pool2 --cluster=$clusterName --disk-type=$diskType --machine-type=$machineType \
--num-nodes=$initialNodeCount --max-nodes=$maxNodeCount --min-nodes=$minNodeCount --disk-size=$disksize --zone=$zone \
--node-labels=whitelist=betradar,nodetype=fast --node-taints=fast_node=only:NoSchedule \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade

echo "-- save node's names of new pool
--"
count=1
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$pool2 -o=name); do
    export nodes$count=${node#*/}
    let count+=1
done


tempnode=`gcloud compute instances list | grep $IP3 | awk '{print $1}'`
if [ ! -z "$tempnode" ];then gcloud --quiet compute instances delete-access-config $tempnode --access-config-name "external-nat";gcloud --quiet compute instances add-access-config $tempnode --access-config-name "external-nat"; fi
unset tempnode

gcloud --quiet compute instances delete-access-config $nodes1 --access-config-name "external-nat"
gcloud --quiet compute instances add-access-config $nodes1 --access-config-name "external-nat" --address $IP3

echo "-- cordon old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool2 -o=name); do
  kubectl cordon "$node";
done

echo "-- drain old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool2 -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-local-data --grace-period=45 "$node";
done

#------------------------------------------------------------------------------------------------------------------------
echo "-- save params"
while IFS= read -r line
do
  case $line in
    *diskType*)
      diskType=$(sed -n 's/diskType: //p' <<< $line) ;;
    *machineType*)
      machineType=$(sed -n 's/machineType: //p' <<< $line) ;;
    *maxNodeCount*)
      maxNodeCount=$(sed -n 's/maxNodeCount: //p' <<< $line) ;;
    *minNodeCount*)
      minNodeCount=$(sed -n 's/minNodeCount: //p' <<< $line) ;;
  esac
done < <(gcloud container node-pools describe --cluster=$clusterName $oldpool3)

initialNodeCount=$(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool3 -o=name | wc -l)

echo "--create review pool
--"
gcloud --quiet container node-pools create $pool3 --cluster=$clusterName --disk-type=$diskType --machine-type=$machineType \
--num-nodes=$initialNodeCount --max-nodes=$maxNodeCount --min-nodes=$minNodeCount --disk-size=$disksize --zone=$zone \
--node-labels=nodetype=review --node-taints=review_node=only:NoSchedule \
--metadata disable-legacy-endpoints=true --enable-autorepair --enable-autoscaling --no-enable-autoupgrade --preemptible

echo "-- cordon old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool3 -o=name); do
  kubectl cordon "$node";
done

echo "-- drain old pools
--"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool3 -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-local-data --grace-period=45 "$node";
done

#------------------------------------------------------------------------------------------------------------------------
echo "-- delete old pools"
gcloud --quiet container node-pools delete $oldpool1 --cluster=$clusterName
gcloud --quiet container node-pools delete $oldpool2 --cluster=$clusterName
gcloud --quiet container node-pools delete $oldpool3 --cluster=$clusterName