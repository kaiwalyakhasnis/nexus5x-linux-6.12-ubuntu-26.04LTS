#!/bin/sh
# demo-take.sh [OUT]: on the phone, as root, on Lomiri's home screen: record the
# panel while fake touches open the indicator panel and Settings (coordinates
# for GridUnit 21). Real time, nothing is sped up.
OUT=${1:-/dev/shm/demo.rec}
taskset -c 5 fbrec "$OUT" 30 &
sleep 1.5
nexus-touch swipe 930 5 930 1100 500	# pull the panel down
sleep 2.5
nexus-touch tap 345 55			# Sound tab
sleep 2.5
nexus-touch swipe 540 1900 540 200 400	# close it
sleep 2
nexus-touch tap 84 1530			# launcher: Settings
sleep 8
nexus-touch swipe 540 500 540 700 300	# first touch only gives Settings focus
sleep 1
nexus-touch tap 820 1225		# Sound page
sleep 3
nexus-touch tap 60 125			# back
sleep 2
nexus-touch swipe 540 1500 540 500 500	# scroll the list
wait
