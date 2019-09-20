#!/bin/bash
set -o errexit -o nounset

configFile=/var/lib/rabbitmq.conf

# http://stackoverflow.com/a/2705678/433558
sed_escape_lhs() {
	echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
}
sed_escape_rhs() {
	echo "$@" | sed -e 's/[\/&]/\\&/g'
}

rabbit_set_config() {
	local key="$1"; shift
	local val="$1"; shift

	[ -e "$configFile" ] || touch "$configFile"

  local sedKey
  local sedVal
	sedKey="$(sed_escape_lhs "$key")"
	sedVal="$(sed_escape_rhs "$val")"
	sed -ri \
		"s/^[[:space:]]*(${sedKey}[[:space:]]*=[[:space:]]*)\S.*\$/\1${sedVal}/" \
		"$configFile"
	if ! grep -qE "^${sedKey}[[:space:]]*=" "$configFile"; then
		echo "$key = $val" >> "$configFile"
	fi
}

rabbit_set_config 'default_user' "$RABBITMQ_DEFAULT_USER"
rabbit_set_config 'default_pass' "$RABBITMQ_DEFAULT_PASS"

rabbit_comment_config() {
	local key="$1"; shift
	[ -e "$configFile" ] || touch "$configFile"
	local sedKey
	sedKey="$(sed_escape_lhs "$key")"
	sed -ri \
		"s/^[[:space:]]*#?[[:space:]]*(${sedKey}[[:space:]]*=[[:space:]]*\S.*)\$/# \1/" \
		"$configFile"
}

# update cookie file
cookieFile='/var/lib/rabbitmq/.erlang.cookie'
if [ -e "$cookieFile" ]; then
		if [ "$(cat "$cookieFile" 2>/dev/null)" != "$RABBITMQ_ERLANG_COOKIE" ]; then
			echo >&2
			echo >&2 "warning: $cookieFile contents do not match RABBITMQ_ERLANG_COOKIE"
			echo >&2
		fi
else
		echo "$RABBITMQ_ERLANG_COOKIE" > "$cookieFile"
fi
chmod 600 "$cookieFile"

# determine whether to set "vm_memory_high_watermark" (based on cgroups)
memTotalKb=
if [ -r /proc/meminfo ]; then
  memTotalKb="$(awk -F ':? +' '$1 == "MemTotal" { print $2; exit }' /proc/meminfo)"
fi
memLimitB=
if [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
  # "18446744073709551615" is a valid value for "memory.limit_in_bytes", which is too big for Bash math to handle
  # "$(( 18446744073709551615 / 1024 ))" = 0; "$(( 18446744073709551615 * 40 / 100 ))" = 0
  memLimitB="$(awk -v totKb="$memTotalKb" '{
    limB = $0;
    limKb = limB / 1024;
    if (!totKb || limKb < totKb) {
      printf "%.0f\n", limB;
    }
  }' /sys/fs/cgroup/memory/memory.limit_in_bytes)"
fi
if [ -n "$memLimitB" ]; then
  # if we have a cgroup memory limit, let's inform RabbitMQ of what it is (so it can calculate vm_memory_high_watermark properly)
  # https://github.com/rabbitmq/rabbitmq-server/pull/1234
  rabbit_set_config 'total_memory_available_override_value' "$memLimitB"
fi
# https://www.rabbitmq.com/memory.html#memsup-usage
if [ "${RABBITMQ_VM_MEMORY_HIGH_WATERMARK:-}" ]; then
  # https://github.com/docker-library/rabbitmq/pull/105#issuecomment-242165822
  vmMemoryHighWatermark="$(
    echo "$RABBITMQ_VM_MEMORY_HIGH_WATERMARK" | awk '
      /^[0-9]*[.][0-9]+$|^[0-9]+([.][0-9]+)?%$/ {
        perc = $0;
        if (perc ~ /%$/) {
          gsub(/%$/, "", perc);
          perc = perc / 100;
        }
        if (perc > 1.0 || perc < 0.0) {
          printf "error: invalid percentage for vm_memory_high_watermark: %s (must be >= 0%%, <= 100%%)\n", $0 > "/dev/stderr";
          exit 1;
        }
        printf "vm_memory_high_watermark.relative %0.03f\n", perc;
        next;
      }
      /^[0-9]+$/ {
        printf "vm_memory_high_watermark.absolute %s\n", $0;
        next;
      }
      /^[0-9]+([.][0-9]+)?[a-zA-Z]+$/ {
        printf "vm_memory_high_watermark.absolute %s\n", $0;
        next;
      }
      {
        printf "error: unexpected input for vm_memory_high_watermark: %s\n", $0;
        exit 1;
      }
    '
  )"
  if [ "$vmMemoryHighWatermark" ]; then
    vmMemoryHighWatermarkKey="${vmMemoryHighWatermark%% *}"
    vmMemoryHighWatermarkVal="${vmMemoryHighWatermark#$vmMemoryHighWatermarkKey }"
    rabbit_set_config "$vmMemoryHighWatermarkKey" "$vmMemoryHighWatermarkVal"
    case "$vmMemoryHighWatermarkKey" in
      # make sure we only set one or the other
      'vm_memory_high_watermark.absolute') rabbit_comment_config 'vm_memory_high_watermark.relative' ;;
      'vm_memory_high_watermark.relative') rabbit_comment_config 'vm_memory_high_watermark.absolute' ;;
    esac
  fi
fi

# starts a rabbitmq node
RABBITMQ_NODENAME=rabbit@localhost rabbitmq-server
