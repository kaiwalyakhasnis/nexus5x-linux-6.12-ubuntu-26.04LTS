#!/bin/sh
# demo-take.sh [OUT]: on the phone, as root, on Lomiri's home screen: record the
# panel while a fake touch taps the Ubuntu icon and the app tray opens
# (coordinates for GridUnit 21). Real time, nothing is sped up.
OUT=${1:-/dev/shm/demo.rec}
taskset -c 5 fbrec "$OUT" 5 &
sleep 1.5
nexus-touch tap 84 1840
wait
