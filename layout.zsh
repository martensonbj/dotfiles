# layout — tile Ghostty windows across the screen
#
# Usage:
#   layout 4  [dir1 dir2 dir3 dir4]   — four quadrants
#   layout 2v [dir1 dir2]             — two vertical halves (left/right)
#   layout 2h [dir1 dir2]             — two horizontal halves (top/bottom)
#   layout 2  [dir1 dir2]             — alias for 2v
#
# If enough Ghostty windows are already open, they are repositioned as-is.
# New windows are only opened to fill any shortfall.
# Directories default to LAYOUT_DIRS; only used when opening new windows.

LAYOUT_DIRS=(
  "$HOME/Sites/homebotapp/surfaces"         # 1: top-left   / left
  "$HOME/Sites/homebotapp"                  # 2: top-right  / right
  "$HOME/Sites/homebotapp/surfaces-reviews" # 3: bottom-left
  "$HOME/Sites/customer-admin"              # 4: bottom-right
)

layout() {
  local mode="${1:-4}"
  shift

  local dims
  dims=$(osascript -e '
    tell application "Finder"
      set b to bounds of window of desktop
      return ((item 3 of b) as string) & " " & ((item 4 of b) as string)
    end tell
  ' 2>/dev/null)

  if [[ -z "$dims" ]]; then
    print -P "%F{red}layout: could not get screen dimensions%f"
    return 1
  fi

  local sw=${dims% *} sh=${dims#* }
  local top=25
  local uh=$(( sh - top ))
  local hw=$(( sw / 2 ))
  local hh=$(( uh / 2 ))

  local -a geoms dirs

  case "$mode" in
    4)
      geoms=(
        "0   $top        $hw $hh"
        "$hw $top        $hw $hh"
        "0   $((top+hh)) $hw $hh"
        "$hw $((top+hh)) $hw $hh"
      )
      dirs=(
        "${1:-${LAYOUT_DIRS[1]}}"
        "${2:-${LAYOUT_DIRS[2]}}"
        "${3:-${LAYOUT_DIRS[3]}}"
        "${4:-${LAYOUT_DIRS[4]}}"
      )
      ;;
    2|2v)
      # 4 windows in quadrants, grouped by column:
      # left: surfaces (top), homebotapp (bottom)
      # right: surfaces-reviews (top), customer-admin (bottom)
      geoms=(
        "0   $top        $hw $hh"
        "$hw $top        $hw $hh"
        "0   $((top+hh)) $hw $hh"
        "$hw $((top+hh)) $hw $hh"
      )
      dirs=(
        "${1:-${LAYOUT_DIRS[1]}}"
        "${2:-${LAYOUT_DIRS[3]}}"
        "${3:-${LAYOUT_DIRS[2]}}"
        "${4:-${LAYOUT_DIRS[4]}}"
      )
      ;;
    2h)
      geoms=(
        "0 $top        $sw $hh"
        "0 $((top+hh)) $sw $hh"
      )
      dirs=(
        "${1:-${LAYOUT_DIRS[1]}}"
        "${2:-${LAYOUT_DIRS[2]}}"
      )
      ;;
    *)
      print "usage: layout [4|2v|2h] [dir1 dir2 ...]"
      return 1
      ;;
  esac

  local n=${#geoms[@]}

  # Start Ghostty if it isn't running at all
  if ! pgrep -xq Ghostty; then
    open -a Ghostty
    sleep 1.5
  else
    osascript -e 'tell application "Ghostty" to activate' 2>/dev/null
  fi

  # Count existing windows
  local existing
  existing=$(osascript -e '
    tell application "System Events"
      tell process "Ghostty"
        return count of windows
      end tell
    end tell
  ' 2>/dev/null)
  existing=${existing:-0}

  # Open new windows only for the shortfall, navigating each to its directory
  for (( i = existing + 1; i <= n; i++ )); do
    local d="${dirs[$i]}"

    osascript -e '
      tell application "System Events"
        tell process "Ghostty"
          keystroke "n" using command down
        end tell
      end tell
    ' 2>/dev/null
    sleep 0.6

    printf '%s' "cd $d" | pbcopy
    osascript -e '
      tell application "System Events"
        tell process "Ghostty"
          keystroke "v" using command down
          key code 36
        end tell
      end tell
    ' 2>/dev/null
    sleep 0.3
  done

  # Position all windows into the layout
  for (( i = 1; i <= n; i++ )); do
    local g="${geoms[$i]}"
    local gx gy gw gh
    read -r gx gy gw gh <<< "$g"

    osascript << ASCRIPT 2>/dev/null
tell application "System Events"
  tell process "Ghostty"
    set position of window $i to {$gx, $gy}
    set size of window $i to {$gw, $gh}
  end tell
end tell
ASCRIPT
  done

  printf '' | pbcopy
}
