#!/bin/bash

echo "Restarting VMware Tools services..."

killall -q vmtoolsd 2>/dev/null
killall -q vmware-user 2>/dev/null

sleep 2

sudo systemctl restart open-vm-tools.service 2>/dev/null || true

sleep 2

/usr/bin/vmware-user-suid-wrapper &

echo "VMware file drag-and-drop services restarted."
echo "Try dragging a file from the host into the VM now."
