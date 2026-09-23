#!/bin/bash
# step3: the learner ran `openstack server list --all-projects --long` and saved it.
# Verified through the saved output: it must contain vm1's ID and the project ID the
# instance belongs to (that column is only printed when -c 'Project ID' asks for it).
out=~/all-servers.txt
[ -s "$out" ] || { labmsg step3m1; exit 1; }
vm_id=$(openstack server show vm1 -f value -c id 2>/dev/null)
[ -n "$vm_id" ] || { labmsg step3m2; exit 1; }
grep -q "$vm_id" "$out" || { labmsg step3m3; exit 1; }
project_id=$(openstack token issue -f value -c project_id 2>/dev/null)
[ -n "$project_id" ] || { labmsg step3m4; exit 1; }
grep -q "$project_id" "$out" || { labmsg step3m5; exit 1; }
labmsg step3m6
