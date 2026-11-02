# . tools/mesa/env.sh (on the phone): run programs on the A418 Mesa in
# /opt/mesa-a418 (tools/mesa/build-on-phone.sh) instead of the system's.
L=/opt/mesa-a418/lib/aarch64-linux-gnu
export LD_LIBRARY_PATH=$L${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export LIBGL_DRIVERS_PATH=$L/dri
export GBM_BACKENDS_PATH=$L/gbm
