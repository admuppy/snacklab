#!/bin/bash
getent group ops >/dev/null || { labmsg step2m1; exit 1; }
id -nG deploy 2>/dev/null | tr ' ' '\n' | grep -qx ops || { labmsg step2m2; exit 1; }
prim=$(id -gn deploy)
[ "$prim" != "ops" ] || { labmsg step2m3; exit 1; }
labmsg step2m4
