#!/bin/bash

set -euo pipefail
[[ ${DEBUG:-} ]] && set -x

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"

zig build
export VLC_PLUGIN_PATH=$HERE/zig-out/lib
# cvlc --no-plugins-cache --plugins-scan -vvv --list 2>&1 | head -50
cvlc --no-plugins-cache --plugins-scan -vvv $HOME/Music/Herbert-Scale/02.The_Movers_And_The_Shakers.flac

# cvlc --no-plugins-cache --plugins-scan -vvv -p panner 2>&1 | head -50
