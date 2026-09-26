#!/bin/bash
set -e
mkdir -p ~/work
cat > ~/work/sysinfo.sh <<'S'
#!/bin/bash
set -euo pipefail
echo "host=$(uname -n)"
echo "uptime=$(awk '{print $1}' /proc/uptime)"
S
chmod +x ~/work/sysinfo.sh
cat > ~/work/logcut.sh <<'S'
#!/bin/bash
set -euo pipefail
usage() { echo "usage: $0 <logfile> <status>" >&2; exit 2; }
[ $# -eq 2 ] || usage
file=$1; code=$2
[ -f "$file" ] || usage
grep -c "status=$code " "$file" || true
S
chmod +x ~/work/logcut.sh
cat > ~/work/withtmp.sh <<'S'
#!/bin/bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "working in $tmp" >&2
date > "$tmp/scratch.txt"
echo "$tmp"
S
chmod +x ~/work/withtmp.sh
cat > ~/work/backup-fixed.sh <<'S'
#!/bin/bash
set -euo pipefail
src=$1
dest=/tmp/backup-$(date +%s%N)
mkdir -p "$dest"
cp -r "$src"/* "$dest"/
echo "backup of $src complete: $dest"
S
chmod +x ~/work/backup-fixed.sh
