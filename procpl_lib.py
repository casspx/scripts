__author__ = 'C2'
import re

# Runbooks
rb_etcd1 = 'https://portworx.atlassian.net/wiki/spaces/PE/pages/392757249/ETCD+Troubleshooting'
rb_dmthin1 = 'https://portworx.atlassian.net/wiki/spaces/PE/pages/2469396955/Runbook+Dmthin'
rb_nfs1 = 'https://purestorage.stackenterprise.co/questions/2437'
rb_lic1 = 'https://portworx.atlassian.net/wiki/spaces/PE/pages/1913847912/Runbook+PX+Licensing'
rb_install1 = 'https://portworx.atlassian.net/wiki/spaces/PE/pages/2143486077/Runbook+PX+kernel+modules+and+other+package+installs'

# ETCD patterns
#re_etcd1 = r'etcdserver: failed to reach the peerURL(http://70.0.87.95:2380) of member eddd950068eba9d'
re_etcd1 = r'etcdserver: failed to reach the peerURL(.*) of member \S*'
re_etcd2 = r'etcdserver: cannot get the version of member'
re_etcd3 = r'wal: sync duration of'
re_etcd4 = r'etcdserver: mvcc: database space exceeded'
re_etcd5 = r'kvdb error: etcdserver: request timed out, retry count'

# NFS Patterns
re_nfs1 = r'timeout expired waiting for volumes to attach or mount for pod'

# dmthin patterns
#re_dmthin1 = r'Insufficient free extents (55211) in volume group pwx0: 128000 required'
re_dmthin1 = r'Insufficient free extents \(\S*\) in volume group \S*: \S* required'
#re_dmthin2 = r'Thin pool pwx0-pxpool-tpool (253:17) transaction_id is 11, while expected 13'
re_dmthin2 = r'Thin pool pwx0-pxpool-tpool \(\S*\) transaction_id is \S*, while expected \S*'
re_dmthin3 = r'Couldn\'t find device with uuid(.*)'

# License patterns
re_lic1 = r'INVALID LICENSE \(ERROR: License does not match PX Cluster identity\)'

# Install patterns
#re_install1 = r'Failed to find patch fs dependency for this kernel <kernel>, exiting...'
#re_install2 = r'Failed to find patch fs dependency on remote site for kernel <kernel>, exiting...'
#re_install3 = r'Failed to parse remote patch fs archive entry for kernel <kernel>, exiting...'
#re_install4 = r'Failed to parse patch fs archive entry for kernel <kernel>, exiting...'
#re_install5 = r'Failed to extract patch fs dependency for kernel <kernel>, exiting...'
#re_install6 = r'Failed to execute patch fs for kernel <kernel>, exiting...'
re_inst1 = r'Failed to (find|parse|extract|execute) (patch|remote.*) fs(.*) kernel(.*)'
#re_inst2 = r'insmod: WARNING: could not insert module <file>: <error>. Check dmesg for more information'
re_inst2 = r'insmod: WARNING: could not insert module \S* \S*. Check dmesg for more information'
re_inst3 = r'Failed to load PX filesystem dependencies for kernel \S*'

# Compile re
re_etcd = re.compile("%s|%s|%s|%s|%s" % (re_etcd1, re_etcd2, re_etcd3, re_etcd4, re_etcd5))
re_dmthin = re.compile("%s|%s|%s" % (re_dmthin1, re_dmthin2, re_dmthin3))
re_nfs =  re.compile("%s" % (re_nfs1))
re_lic = re.compile("%s" % (re_lic1))
re_inst = re.compile("%s|%s|%s" % (re_inst1, re_inst2, re_inst3))

# PX software components
px_component = ["kvdb", "dmthin", "nfs", "lic", "install", "all"]

# Count total patterns found in the log
pattern_found = 0
def etcd_psearch(etcd_found, fline):
    global pattern_found
    if re_etcd.search(fline):
        etcd_found.append(fline.strip())
        pattern_found += 1
def dmthin_psearch(dmthin_found, fline):
    global pattern_found
    if re_dmthin.search(fline):
        dmthin_found.append(fline.strip())
        pattern_found += 1
def nfs_psearch(nfs_found, fline):
    global pattern_found
    if re_nfs.search(fline):
        nfs_found.append(fline.strip())
        pattern_found += 1
def lic_psearch(lic_found, fline):
    global pattern_found
    if re_lic.search(fline):
        lic_found.append(fline.strip())
        pattern_found += 1
def inst_psearch(inst_found, fline):
    global pattern_found
    if re_inst.search(fline):
        inst_found.append(fline.strip())
        pattern_found += 1

#eof