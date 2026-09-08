#!/bin/sh
# Author:
#   github/tstromberg
#   source: https://gist.github.com/tstromberg/1e097edb2dbab3e8464b5908192e601d

#
# brightnessctl - FreeBSD compatibility wrapper
# Translates brightnessctl commands to FreeBSD equivalents
# Supports: sysctl (ACPI), backlight(8), and xbacklight as backends
#
# Compatible with ly display manager and real brightnessctl syntax
#

set -e

# Configuration (avoid 'local' for POSIX compliance)
BACKEND=""
DEVICE=""
DEVICE_CLASS="backlight"
QUIET=0
PRETEND=0
MACHINE_READABLE=0
PERCENTAGE_GET=0
MIN_VALUE=1
VERSION="0.1.0-freebsd"

# ACPI sysctl paths to try
SYSCTL_PATHS="hw.acpi.video.lcd0.brightness hw.acpi.video.lcd1.brightness hw.backlight.brightness"

# Detect available backend
detect_backend() {
    # Prefer FreeBSD native backlight(8) if available
    if command -v backlight >/dev/null 2>&1; then
        BACKEND="backlight"
        return 0
    fi

    # Try sysctl ACPI brightness
    for path in $SYSCTL_PATHS; do
        if sysctl -n "$path" >/dev/null 2>&1; then
            BACKEND="sysctl"
            DEVICE="$path"
            return 0
        fi
    done

    # Fall back to xbacklight (X11)
    if command -v xbacklight >/dev/null 2>&1; then
        BACKEND="xbacklight"
        return 0
    fi

    echo "Failed to find a suitable device." >&2
    exit 1
}

# Get current brightness (0-100 or raw value depending on backend)
get_brightness() {
    case "$BACKEND" in
        backlight)
            backlight 2>/dev/null | sed 's/brightness: //' | sed 's/%//'
            ;;
        sysctl)
            sysctl -n "$DEVICE" 2>/dev/null
            ;;
        xbacklight)
            xbacklight -get 2>/dev/null | cut -d. -f1
            ;;
    esac
}

# Get maximum brightness value
get_max() {
    case "$BACKEND" in
        backlight)
            echo "100"
            ;;
        sysctl)
            # ACPI brightness is typically 0-100, but check for max
            max_path="${DEVICE%brightness}levels"
            if sysctl -n "$max_path" >/dev/null 2>&1; then
                sysctl -n "$max_path" | tr ' ' '\n' | sort -n | tail -1
            else
                echo "100"
            fi
            ;;
        xbacklight)
            echo "100"
            ;;
    esac
}

# Get device name for output
get_device_name() {
    case "$BACKEND" in
        backlight)  echo "backlight" ;;
        sysctl)     echo "$DEVICE" ;;
        xbacklight) echo "xbacklight" ;;
    esac
}

# Set brightness - handles absolute, percentage, and relative values
# Supports BOTH syntaxes:
#   +10%, -10%  (leading sign)
#   10%+, 10%-  (trailing sign - what ly uses)
#   +10, -10    (leading sign absolute)
#   10+, 10-    (trailing sign absolute)
set_brightness() {
    value="$1"
    current=$(get_brightness)
    max=$(get_max)

    # Parse the value - check trailing operators FIRST (brightnessctl canonical form)
    case "$value" in
        *%+)
            # Trailing plus percentage: 10%+
            delta="${value%\%+}"
            new_value=$((current + (max * delta / 100)))
            ;;
        *%-)
            # Trailing minus percentage: 10%-  (THIS IS WHAT LY USES)
            delta="${value%\%-}"
            new_value=$((current - (max * delta / 100)))
            ;;
        *+)
            # Trailing plus absolute: 10+
            delta="${value%+}"
            new_value=$((current + delta))
            ;;
        *-)
            # Trailing minus absolute: 10-
            delta="${value%-}"
            new_value=$((current - delta))
            ;;
        +*%)
            # Leading plus percentage: +10%
            delta="${value#+}"
            delta="${delta%\%}"
            new_value=$((current + (max * delta / 100)))
            ;;
        -*%)
            # Leading minus percentage: -10%
            delta="${value#-}"
            delta="${delta%\%}"
            new_value=$((current - (max * delta / 100)))
            ;;
        +*)
            # Leading plus absolute: +10
            delta="${value#+}"
            new_value=$((current + delta))
            ;;
        -*)
            # Leading minus absolute: -10
            delta="${value#-}"
            new_value=$((current - delta))
            ;;
        *%)
            # Absolute percentage: 50%
            pct="${value%\%}"
            new_value=$((max * pct / 100))
            ;;
        *)
            # Absolute value: 50
            new_value="$value"
            ;;
    esac

    # Clamp to valid range (respecting min_value)
    [ "$new_value" -lt "$MIN_VALUE" ] && new_value="$MIN_VALUE"
    [ "$new_value" -gt "$max" ] && new_value="$max"

    # Pretend mode - don't actually change
    if [ "$PRETEND" -eq 1 ]; then
        [ "$QUIET" -eq 0 ] && print_status "$new_value" "$max"
        return 0
    fi

    # Apply the brightness
    case "$BACKEND" in
        backlight)
            backlight "$new_value" 2>/dev/null
            ;;
        sysctl)
            sysctl "$DEVICE=$new_value" >/dev/null 2>&1
            ;;
        xbacklight)
            xbacklight -set "$new_value" 2>/dev/null
            ;;
    esac

    [ "$QUIET" -eq 0 ] && print_status
}

# Print current status (mimics brightnessctl output format exactly)
print_status() {
    # Allow override for pretend mode
    if [ -n "$1" ]; then
        current="$1"
        max="$2"
    else
        current=$(get_brightness)
        max=$(get_max)
    fi
    
    if [ "$max" -gt 0 ]; then
        pct=$((current * 100 / max))
    else
        pct=0
    fi

    device_name=$(get_device_name)

    if [ "$MACHINE_READABLE" -eq 1 ]; then
        # Machine readable format: device,class,current,percentage,max
        echo "${device_name},${DEVICE_CLASS},${current},${pct}%,${max}"
    else
        # Human readable format (matches real brightnessctl)
        cat <<EOF
Device '${device_name}' of class '${DEVICE_CLASS}':
	Current brightness: ${current} (${pct}%)
	Max brightness: ${max}
EOF
    fi
}

# List available devices (matches brightnessctl -l output format)
list_devices() {
    # Check backlight(8)
    if command -v backlight >/dev/null 2>&1; then
        val=$(backlight 2>/dev/null | sed 's/brightness: //' | sed 's/%//' || echo "0")
        if [ "$MACHINE_READABLE" -eq 1 ]; then
            echo "backlight,backlight,${val},${val}%,100"
        else
            cat <<EOF
Device 'backlight' of class 'backlight':
	Current brightness: ${val} (${val}%)
	Max brightness: 100
EOF
        fi
    fi

    # Check sysctl paths
    for path in $SYSCTL_PATHS; do
        if sysctl -n "$path" >/dev/null 2>&1; then
            val=$(sysctl -n "$path")
            if [ "$MACHINE_READABLE" -eq 1 ]; then
                echo "${path},backlight,${val},${val}%,100"
            else
                cat <<EOF
Device '${path}' of class 'backlight':
	Current brightness: ${val} (${val}%)
	Max brightness: 100
EOF
            fi
        fi
    done

    # Check xbacklight
    if command -v xbacklight >/dev/null 2>&1; then
        val=$(xbacklight -get 2>/dev/null | cut -d. -f1 || echo "0")
        if [ "$MACHINE_READABLE" -eq 1 ]; then
            echo "xbacklight,backlight,${val},${val}%,100"
        else
            cat <<EOF
Device 'xbacklight' of class 'backlight':
	Current brightness: ${val} (${val}%)
	Max brightness: 100
EOF
        fi
    fi
}

# Save current brightness
save_brightness() {
    current=$(get_brightness)
    device_name=$(get_device_name)
    save_file="/tmp/.brightnessctl-${device_name}"
    echo "$current" > "$save_file"
    [ "$QUIET" -eq 0 ] && echo "Saved brightness: $current"
}

# Restore saved brightness
restore_brightness() {
    device_name=$(get_device_name)
    save_file="/tmp/.brightnessctl-${device_name}"
    if [ -f "$save_file" ]; then
        saved=$(cat "$save_file")
        set_brightness "$saved"
    else
        echo "No saved state found for $device_name" >&2
        exit 1
    fi
}

# Print help
usage() {
    cat <<EOF
brightnessctl ${VERSION} - FreeBSD compatibility wrapper
Usage: brightnessctl [options] [operation] [value]
Operations:
    i, info         Get device info (default)
    g, get          Get current brightness value
    m, max          Get maximum brightness value
    s, set VALUE    Set brightness to VALUE
Values for 'set':
    N               Absolute value
    N%              Percentage of max
    +N% or N%+      Increase by N% (both syntaxes supported)
    -N% or N%-      Decrease by N% (both syntaxes supported)
    +N or N+        Increase by N
    -N or N-        Decrease by N
Options:
    -l, --list              List devices with available brightness controls
    -q, --quiet             Suppress output
    -p, --pretend           Do not perform write operations
    -m, --machine-readable  Produce machine-readable output
    -n, --min-value=N       Set minimum brightness (default: 1)
    -s, --save              Save state in a temporary file
    -r, --restore           Restore previously-saved state
    -d, --device=DEVICE     Specify device name
    -c, --class=CLASS       Specify device class
    -v, --version           Print version and exit
    -h, --help              Show this help
FreeBSD Backends (auto-detected):
    backlight       FreeBSD native backlight(8)
    sysctl          ACPI via sysctl hw.acpi.video.*
    xbacklight      X11 xbacklight
Examples:
    brightnessctl                  Show current brightness
    brightnessctl s 50%            Set to 50%
    brightnessctl s 5%+            Increase by 5%
    brightnessctl s 5%-            Decrease by 5% (ly syntax)
    brightnessctl set +10%         Increase by 10%
    brightnessctl g                Get raw value
    brightnessctl -m g             Get value in machine format
EOF
}

# Print version
print_version() {
    echo "brightnessctl ${VERSION}"
}

# Parse arguments
OPERATION=""
VALUE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -l|--list)
            [ -z "$BACKEND" ] || true  # Don't require backend for list
            list_devices
            exit 0
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -p|--pretend)
            PRETEND=1
            shift
            ;;
        -m|--machine-readable)
            MACHINE_READABLE=1
            shift
            ;;
        -n|--min-value|--min-value=*)
            if [ "$1" = "-n" ] || [ "$1" = "--min-value" ]; then
                shift
                MIN_VALUE="$1"
            else
                MIN_VALUE="${1#*=}"
            fi
            shift
            ;;
        -s|--save)
            [ -z "$BACKEND" ] && detect_backend
            save_brightness
            exit 0
            ;;
        -r|--restore)
            [ -z "$BACKEND" ] && detect_backend
            restore_brightness
            exit 0
            ;;
        -d|--device|--device=*)
            if [ "$1" = "-d" ] || [ "$1" = "--device" ]; then
                shift
                device_arg="$1"
            else
                device_arg="${1#*=}"
            fi
            case "$device_arg" in
                backlight)
                    BACKEND="backlight"
                    ;;
                xbacklight)
                    BACKEND="xbacklight"
                    ;;
                hw.*|acpi*)
                    BACKEND="sysctl"
                    DEVICE="$device_arg"
                    ;;
                \*|'*')
                    # Wildcard - use auto-detection but only backlight class
                    DEVICE_CLASS="backlight"
                    ;;
                *)
                    # Try to find matching device
                    for path in $SYSCTL_PATHS; do
                        case "$path" in
                            *"$device_arg"*)
                                BACKEND="sysctl"
                                DEVICE="$path"
                                break
                                ;;
                        esac
                    done
                    if [ -z "$BACKEND" ]; then
                        echo "Device '$device_arg' not found." >&2
                        exit 1
                    fi
                    ;;
            esac
            shift
            ;;
        -c|--class|--class=*)
            if [ "$1" = "-c" ] || [ "$1" = "--class" ]; then
                shift
                DEVICE_CLASS="$1"
            else
                DEVICE_CLASS="${1#*=}"
            fi
            shift
            ;;
        -v|--version)
            print_version
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -P|--percentage)
            PERCENTAGE_GET=1
            shift
            ;;
        # Short operation aliases (brightnessctl canonical)
        i|info)
            OPERATION="info"
            shift
            ;;
        g|get)
            OPERATION="get"
            shift
            ;;
        m|max)
            OPERATION="max"
            shift
            ;;
        s|set)
            OPERATION="set"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Try 'brightnessctl --help' for more information." >&2
            exit 1
            ;;
        *)
            # Could be a value or unknown operation
            if [ -z "$OPERATION" ]; then
                # Might be a value passed without 'set' command
                # Real brightnessctl requires operation, but be lenient
                VALUE="$1"
            else
                VALUE="$1"
            fi
            shift
            ;;
    esac
done

# Auto-detect backend if not specified
[ -z "$BACKEND" ] && detect_backend

# Execute operation
case "$OPERATION" in
    ""|info)
        print_status
        ;;
    get)
        current=$(get_brightness)
        if [ "$PERCENTAGE_GET" -eq 1 ]; then
            max=$(get_max)
            if [ "$max" -gt 0 ]; then
                pct=$((current * 100 / max))
            else
                pct=0
            fi
            echo "${pct}%"
        else
            echo "$current"
        fi
        ;;
    max)
        get_max
        ;;
    set)
        if [ -z "$VALUE" ]; then
            echo "brightnessctl: 'set' requires a value" >&2
            exit 1
        fi
        set_brightness "$VALUE"
        ;;
    *)
        echo "Unknown operation: $OPERATION" >&2
        echo "Try 'brightnessctl --help' for more information." >&2
        exit 1
        ;;
esac
