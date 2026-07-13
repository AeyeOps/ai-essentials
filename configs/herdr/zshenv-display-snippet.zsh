# derive DISPLAY when unset (herdr panes, detached sessions) from the live
# X socket; skipped when SSH X-forwarding or the desktop already set it
if [ -z "$DISPLAY" ]; then
  for _xs in /tmp/.X11-unix/X*(N); do
    export DISPLAY=":${_xs##*/X}"
    break
  done
  unset _xs
  [ -z "$XAUTHORITY" ] && [ -r "/run/user/$UID/gdm/Xauthority" ] && export XAUTHORITY="/run/user/$UID/gdm/Xauthority"
fi
