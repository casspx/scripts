#!/bin/bash
# kvdb recovery script over kubectl
# - Needs at least one kvdb node available 
# - PX ocimon running on the kvdb node where the recovery will be performed
# - User needs to identify the surviving kvdb node and with associated disk healthy
# - Once the kvdb node is identified, script can be executed and the user will be guided along the process
# - Script stops all px nodes, executes kvdb recovery using snapshots, then starts all nodes
# - Written by C2 with guidance by Aditya

# Create a local directory where all files needed for the recovery will be stored
# - Creates kvdb-recovery directory in user's home dir
# - Generates kvdb bootstrap and cloud drive configmaps

(
date

if [ -z $1 ] ; then
  echo "Script runs in dry run mode by default.  Use 'run' arg to initiate kvdb recovery"
fi

DRY_RUN=$1
function execute() {
   if [ "$DRY_RUN" == 'run' ] ; then
     eval "$@"    
   else
     echo "Command: ${@}"
       return 0
   fi
}

DIR="kvdb-recovery"

if [ ! -d ~/$DIR ] ; then 
  echo "Creating ~/$DIR directory"
    mkdir ~/$DIR
elif [ "$DRY_RUN" == 'run' ] ; then 
  echo "Recreating ~/$DIR directory"
    mv ~/$DIR ~/${DIR}.$(date "+%m%d%Y%H%M%S")
      mkdir ~/$DIR
fi

kubectl config current-context
read -p "Enter portworx namespace : " NAMESPACE
kubectl get ns $NAMESPACE

if [ $? -ne 0 ] ; then
  echo "kubectl get ns $NAMESPACE failed.  Script exited."
    exit 1
fi

PXCLUSTER=`kubectl get storagecluster -n $NAMESPACE |grep -v NAME |awk '{print $1}'`
echo "PX cluster ID : $PXCLUSTER"
kubectl get pods -lname=portworx -n $NAMESPACE

if [ $? -ne 0 ] ; then
  echo "kubectl get pods -lname=portworx -n $NAMESPACE |grep px-cluster failed.  Script exited."
    exit 1
fi

read -p "Does the right PX cluster and pods show? (y/n) : " PXPODS

if [ $PXPODS != y ] ; then
  echo "Target PX cluster not confirmed or invalid answer received.  Exiting.."
    exit 1
fi

KVDB_ORIG_YAML="px-bootstrap-orig.yaml"
CLOUDDRIVE_JSON="px-cloud-drive.json"

if [ ! -f ~/$DIR/$KVDB_YAML ] && [ ! -f ~/$DIR/$CLOUDDRIVE_JSON ] ; then 
  echo "Generating configmap files";
    PX_BOOTSTRAP=`kubectl get cm -n kube-system |grep px-bootstrap |awk '{print $1}'`
      kubectl get cm "$PX_BOOTSTRAP" -oyaml -n kube-system > ~/$DIR/$KVDB_ORIG_YAML;
        kubectl get cm -n kube-system |grep px-cloud-drive |awk '{print $1}' | xargs kubectl get cm -ojson -n kube-system > ~/$DIR/$CLOUDDRIVE_JSON;
fi

#  Identify kvdb node that can be used for recovery
# - Expects to see at one kvdb node entry in px-bootstrap cm
# - User selects the kvdb node to recover snapshots from
# - KVDB disk should be attached, unmounted, and healthy

KVDB_JSON="px-kvdb.json"

if [ ! -f ~/$DIR/$KVDB_JSON ] ; then
  echo "Generating kvdb json file from configmap"
    kubectl get cm -n kube-system |grep px-bootstrap |awk '{print $1}' | xargs kubectl get cm -ojson -n kube-system | jq '.data."px-entries" | fromjson' > ~/$DIR/$KVDB_JSON;
fi

KVDB_VAR=`cat ~/$DIR/$KVDB_JSON`
# Uncomment for debugging
# echo $'px-boostrap file\n'"$KVDB_VAR"''

# Read user input 

KVDB_NUM_ENTRIES=`echo $KVDB_VAR |jq '.|length'`
index=0

echo "PX bootstrap kvdb node entries that could be used for recovery" 

while [ "$index" -lt "$KVDB_NUM_ENTRIES" ] ; do
  echo "KVDB Node : $index"
    echo $KVDB_VAR |jq ".[$index]"
      index=`expr $index + 1`
done

echo "$KVDB_NUM_ENTRIES KVDB configmap entry/ies"
read -p "Enter Node Number : " KNODE
read -p "Is the node online and the associated disk is attached and healthy? (y/n) : " KNODESTAT 
echo "KVDB Node $KNODE is selected"

re='^[0-9]+$'

if ! [[ $KNODE =~ $re && "$KNODE" -lt "$KVDB_NUM_ENTRIES" && $KNODESTAT = "y" ]] ; then
  echo "Invalid selection. Exiting.."
    exit 1
fi

KVDB_NODEIP=`jq ".[$KNODE].IP" <<< $KVDB_VAR |sed -e 's/^"//' -e 's/"$//'`
KVDB_ID=`jq ".[$KNODE].ID" <<< $KVDB_VAR |sed -e 's/^"//' -e 's/"$//'`
KVDB_INDEX=`jq ".[$KNODE].Index" <<< $KVDB_VAR |sed -e 's/^"//' -e 's/"$//'`
KVDB_DOMAIN=`jq ".[$KNODE].Domain" <<< $KVDB_VAR |sed -e 's/^"//' -e 's/"$//'`
KVDB_PEERPORT=`jq ".[$KNODE].peerport" <<< $KVDB_VAR |sed -e 's/^"//' -e 's/"$//'`
KVDB_DATADIRTYPE=`jq ".[$KNODE].DataDirType" <<< $KVDB_VAR |sed -e 's/^"//' -e 's/"$//'`

echo "Parsed IP : $KVDB_NODEIP, ID : $KVDB_ID, Index : $KVDB_INDEX, Domain : $KVDB_DOMAIN, PeerPort : $KVDB_PEERPORT, DataDirType : $KVDB_DATADIRTYPE"

# Takes kvdb node index from user input 

KVDB_SINGLE_ENTRY=`jq [.[$KNODE]] ~/$DIR/$KVDB_JSON |jq -c`

# Stop PX 
# - kubectl label nodes px/service=stop
# - Apply new px-bootstrap configmap

execute echo "Stopping PX service on all nodes"
execute kubectl label nodes px/service=stop --all --overwrite

function check_pxpod_down() {
  echo "Waiting for PX pods to go down for up to 15 minutes.."
  wait=0
  while [ "$wait" -le 900 ] ; do
    if [ "$wait" -eq 900 ] ; then
      echo "All PX pods did not terminate. Please make sure all PX pods are down and try the script again.  Exiting"
        exit 1
    fi
    PODS=`kubectl get pods -lname=portworx -n $NAMESPACE |grep -v NAME |awk '{print $2}'`
    if grep -qs "2/2" <<< "$PODS"; then
      sleep 1       
        wait=`expr $wait + 1`
    else
      kubectl get pods -lname=portworx -n $NAMESPACE
        break
    fi 
  done
}

execute check_pxpod_down

# Update px-bootstrap configmap
# - Should have kvdb node entry based on selection
# - Backup original px-bootstrap cm with .orig extension

KVDB_YAML="px-bootstrap.yaml"

function update_bootstrap_file() {
  kubectl annotate cm "$PX_BOOTSTRAP" kubectl.kubernetes.io/last-applied-configuration- -n kube-system
  kubectl get cm "$PX_BOOTSTRAP" -oyaml -n kube-system > ~/$DIR/$KVDB_YAML
  echo "Updating px-bootstrap configmap"
  sed -i '' "s/\[.*\]/${KVDB_SINGLE_ENTRY}/g" ~/$DIR/$KVDB_YAML
  grep "px-entries: " ~/$DIR/$KVDB_YAML | sed 's/^ *//g'
  kubectl apply -f ~/$DIR/$KVDB_YAML
}

execute update_bootstrap_file

# Build etcd restore script
# - Download etcdctl binary
# - Creates etcd-restore.sh

ETCD_RESTORE_FILE="etcd-restore.sh"

if [ ! -f ~/$DIR/$ETCD_RESTORE_FILE ] ; then
  cat << EOF > ~/$DIR/$ETCD_RESTORE_FILE 
#!/bin/bash

touch /var/cores/etcd_recovery_run

ETCD_VER=v3.4.25
GOOGLE_URL=https://storage.googleapis.com/etcd
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
DOWNLOAD_URL=\${GOOGLE_URL}

if [ ! -f /tmp/etcd-download/etcdctl ] ; then
  rm -f /tmp/etcd-\${ETCD_VER}-linux-amd64.tar.gz
    rm -rf /tmp/etcd-download && mkdir -p /tmp/etcd-download
      curl -L \${DOWNLOAD_URL}/\${ETCD_VER}/etcd-\${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-\${ETCD_VER}-linux-amd64.tar.gz
        tar xzvf /tmp/etcd-\${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download --strip-components=1
          rm -f /tmp/etcd-\${ETCD_VER}-linux-amd64.tar.gz
            /tmp/etcd-download/etcd --version
              /tmp/etcd-download/etcdctl version
fi

# Update /etc/hosts file

if ! grep -qs ${KVDB_NODEIP} /etc/hosts; then
  echo "${KVDB_NODEIP} ${KVDB_DOMAIN}" >> /etc/hosts
fi

# Mount kvdb disk and backup kvdb db

KVDB_MOUNT_PATH="/kvdb-recovery"

if [ "$KVDB_DATADIRTYPE" == "KvdbDevice" ] ; then
  KVDB_DISK=\$(sudo blkid |grep kvdbvol |awk -F: '{print \$1}')
    KVDB_DISK_PATH=\$KVDB_MOUNT_PATH
      if grep -qs '/dev/mapper' <<< "\$KVDB_DISK" ; then
        KVDB_DISK=\$(grep '/dev/mapper' <<< "\$KVDB_DISK")
      fi
elif [ "$KVDB_DATADIRTYPE" == "MetadataDevice" ] || [ "$KVDB_DATADIRTYPE" == "BtrfsSubvolume" ] ; then 
  KVDB_DISK=\$(sudo blkid |grep "mdvol" |awk -F: '{print \$1}')
    KVDB_DISK_PATH="\$KVDB_MOUNT_PATH"/.metadata
      if grep -qs '/dev/mapper' <<< "\$KVDB_DISK" ; then
        KVDB_DISK=\$(grep '/dev/mapper' <<< "\$KVDB_DISK")
      else
        KVDB_DISK=\$(head -1 <<< "\$KVDB_DISK")
      fi
fi

if grep -qs \$KVDB_DISK /proc/mounts; then 
  echo "kvdb disk is  mounted. Dismount \$KVDB_DISK and run the script again. Exiting.."
    exit 1
fi

if [ ! -d \$KVDB_MOUNT_PATH ] ; then
  mkdir \$KVDB_MOUNT_PATH;
    mount \$KVDB_DISK \$KVDB_MOUNT_PATH;
      cd \$KVDB_DISK_PATH;
        if [ -d member ] ; then
          mv member member-copy;
            cd \$KVDB_DISK_PATH/member-copy
        else
          echo "KVDB member directory does not exist!. Please verify disk"
            exit 1
        fi
else 
  echo "\$KVDB_MOUNT_PATH mount exists. Terminating.."
    exit 1
fi

export ETCDCTL_API=3
/tmp/etcd-download/etcdctl snapshot restore snap/db --data-dir=\$KVDB_DISK_PATH/member-new \\
  --skip-hash-check=true --name="$KVDB_ID" \\
  --initial-cluster="$KVDB_ID=http://${KVDB_DOMAIN}:${KVDB_PEERPORT}" \\
  --initial-advertise-peer-urls="http://${KVDB_DOMAIN}:${KVDB_PEERPORT}" \\
  --initial-cluster-token="$PXCLUSTER"

if [ \$? -eq 0 ] ; then
  mv \$KVDB_DISK_PATH/member-new/member \$KVDB_DISK_PATH 
    cd /; umount \$KVDB_MOUNT_PATH; rmdir \$KVDB_MOUNT_PATH 
      rm /var/cores/etcd_recovery_run
else
  echo "etcdctl snapshot restore failed"
    exit 1
fi
EOF

fi

chmod u+x ~/$DIR/$ETCD_RESTORE_FILE

# Move etcd restore script to the target node

KVDB_NODEPOD=`kubectl get pods -lname=portworx -n $NAMESPACE -owide| grep "$KVDB_NODEIP"| awk '{print $1}'`
KVDB_NODE=`kubectl get nodes -o wide |grep $KVDB_NODEIP |awk '{print $1}'`
execute kubectl cp ~/$DIR/$ETCD_RESTORE_FILE $NAMESPACE/$KVDB_NODEPOD:/var/cores -c portworx 
execute echo "$ETCD_RESTORE_FILE is copied to ${KVDB_NODEPOD}:/var/cores"
execute kubectl exec $KVDB_NODEPOD -c portworx -n $NAMESPACE -- nsenter --mount=/host_proc/1/ns/mnt /var/cores/etcd-restore.sh

# Double check etcdctl snapshot restore before starting first kvdb node

function check_etdctl_restore_cmd() {
  RUN_STAT="etcdctl_cmd_stat"
  touch ~/$DIR/$RUN_STAT
  kubectl exec $KVDB_NODEPOD -c portworx -n $NAMESPACE -- bash -c "test ! -f /var/cores/etcd_recovery_run" &> ~/$DIR/$RUN_STAT
  if [ ! -s ~/$DIR/$RUN_STAT ] ; then
    echo "Starting kvdb node $KVDB_NODE"
      kubectl label node "$KVDB_NODE" px/service=start --overwrite
  else
    echo "KVDB recovery was unsuccessful.  Please rollback px-bootstrap config map before attempting to run the script again"
      exit 1  
  fi
}

execute check_etdctl_restore_cmd

# Start all nodes
# - Wait at least 5 minutes if first KVDB node has started

function check_first_kvdb_up() {
  echo "Checking if KVDB node has started.  May take up to 5 minutes.."
  count=0 
  while [ "$count" -le 300 ]; do
    KVDB_WAIT=`kubectl logs --since=900s $KVDB_NODEPOD -c portworx -n $NAMESPACE |grep "created kv instance"`
      if ! grep -qs "created kv instance" <<< "$KVDB_WAIT"; then
        sleep 1
          count=`expr $count + 1`
      else
        cat <<< "$KVDB_WAIT"
          break
      fi
  done
  KVDB_NODE_START=`kubectl exec $KVDB_NODEPOD -c portworx -n $NAMESPACE -- /opt/pwx/bin/pxctl service kvdb members`
  if grep -qs "$KVDB_DOMAIN" <<< "$KVDB_NODE_START"; then
    echo "First KVDB node started successfully"    
      cat <<< "$KVDB_NODE_START"
        echo "Starting all PX cluster nodes"
          kubectl label nodes px/service=start --all --overwrite
            echo "KVDB recovery is complete.  Please check PX Cluster" 
  else
    echo "Unable to verify if first KVDB node had started.  Recovery maybe incomplete.  Please check PX Cluster"
  fi
}

execute check_first_kvdb_up
) 2>&1 | tee -a ~/kvdb.log

#eoc 
