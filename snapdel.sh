#!/bin/bash

# Clean up unneeded volume snapshots from backup given an age
# Run storkctl get snap --all-namespaces  |tee /tmp/file.out
# Preserved snaps listed in /tmp/skip.list

FILE="/tmp/file.out"
DRY_RUN=Y

function execute() {
  echo "Command: ${@}"
    if [ $DRY_RUN == 'Y' ]; then
      return 0
    fi
    eval "$@"
}

# Delete snaps older than X days

age='6 months ago'
ageSec=$(date --date "$age" +'%s')

# Count number of snaps in the file

snapCount=`grep -v NAMESPACE $FILE |wc -l`
lineCount=1

# Loop and delete snap when longer than X days

while [ $lineCount -le $snapCount ] ; do
    echo line $lineCount
      snapList=($(cat $FILE |grep -v NAMESPACE |head -${lineCount} |tail -1))
        nameSpace=${snapList[0]}
          snapId=${snapList[1]}
            dateStamp=${snapList[@]:4:5}
              dateStampSec=$(date --date "$dateStamp" +'%s')

   if [ $dateStampSec -lt $ageSec ] ; then
     echo Deleting $snapId ..;
       echo storkctl delete volumesnapshot $snapId -n $nameSpace;
         sleep 1;
   else
     echo "Skipping $snapId" | tee /tmp/skip.list
   fi

   lineCount=`expr ${lineCount} + 1`
done
