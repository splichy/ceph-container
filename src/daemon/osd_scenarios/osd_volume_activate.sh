#!/bin/bash
set -e

function osd_volume_activate {
  check_device

  # Verify the device is a valid ceph-volume device
  # If not the following command will return 1 with "No valid Ceph devices found"
  if ! ceph-volume lvm list "${OSD_DEVICE}"; then
    cat /var/log/ceph
    exit 1
  fi

  # Find the OSD ID
  OSD_ID="$(ceph-volume lvm list "$OSD_DEVICE" --format json | python -c 'import sys, json; print(json.load(sys.stdin).keys()[0])')"

  # Find the OSD FSID
  OSD_FSID="$(ceph-volume lvm list "$OSD_DEVICE" --format json | python -c "import sys, json; print(json.load(sys.stdin)[\"$OSD_ID\"][0][\"tags\"][\"ceph.osd_fsid\"])")"

  # Discover the objectstore
  if [[ "OSD_FILESTORE" -eq 1 ]]; then
    OSD_OBJECTSTORE=(--filestore)
  elif [[ "OSD_BLUESTORE" -eq 1 ]]; then
    OSD_OBJECTSTORE=(--bluestore)
  else
    log "Either OSD_FILESTORE or OSD_BLUESTORE must be set to 1."
    exit 1
  fi

  # Activate the OSD
  # The command can fail so if it does, let's output the ceph-volume logs
  if ! ceph-volume lvm activate --no-systemd "${OSD_OBJECTSTORE[@]}" "${OSD_ID}" "${OSD_FSID}"; then
    cat /var/log/ceph
    exit 1
  fi

  log "SUCCESS"
  # This ensures all resources have been unmounted after the OSD has exited
  # We define `sigterm_cleanup_post` here because:
  # - we want to 'protect' the following `exec` in particular.
  # - having the cleaning code just next to the concerned function in the same file is nice.
  function sigterm_cleanup_post {
    local ceph_mnt
    ceph_mnt=$(findmnt --nofsroot --noheadings --output SOURCE --submounts --target /var/lib/ceph/osd/ | grep '^/')
    for mnt in $ceph_mnt; do
      log "osd_volume_activate: Unmounting $mnt"
      umount "$mnt" || (log "osd_volume_activate: Failed to umount $mnt"; lsof $mnt)
    done
  }
  exec /usr/bin/ceph-osd "${CLI_OPTS[@]}" -f -i "${OSD_ID}"
}
