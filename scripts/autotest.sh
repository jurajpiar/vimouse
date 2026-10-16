#!/bin/sh
# Unattended loop for working on the line provider: whenever HEAD changes, build and
# run the headless probe against the named apps, writing everything to build/probe.log.
# Leave the apps open side by side with documents showing. Keeps the Mac awake.
#
#   scripts/autotest.sh "Markdown Preview" "Brave Browser" Claude
set -u
cd "$(dirname "$0")/.."
mkdir -p build
caffeinate -dims -w $$ &
last=""
echo "autotest: watching for commits (ctrl-c to stop)"
while true; do
  head="$(git rev-parse HEAD 2>/dev/null)"
  if [ -n "$head" ] && [ "$head" != "$last" ]; then
    last="$head"
    {
      echo "== $head $(date '+%H:%M:%S') $(git log -1 --format=%s)"
      if swift build -c release 2>&1 | grep -E "error:|warning: unre" ; then
        echo "BUILD FAILED"
      else
        echo "build ok"
        VIMOUSE_DEBUG=1 .build/release/vimouse --probe "$@" 2>&1 | grep -v "\[[0-9]*\] AX"
      fi
      echo "== done"
    } > build/probe.log.tmp 2>&1
    mv build/probe.log.tmp build/probe.log
  fi
  sleep 5
done
