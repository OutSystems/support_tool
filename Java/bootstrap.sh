#!/bin/bash
TMPDIR=$(mktemp -d)

tail -n +10 $0 | base64 -d | tar zx -C $TMPDIR

cd $TMPDIR
./main.sh
rm -rf $TMPDIR
exit
