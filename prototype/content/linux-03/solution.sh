#!/bin/bash
set -e
mkdir -p ~/work
grep -Ec '" 5[0-9]{2} ' /var/log/lab/access.log > ~/work/err5xx.count
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > ~/work/top-ip.txt
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log > ~/work/access-redacted.log
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s+0}' /var/log/lab/access.log > ~/work/api-bytes.txt
