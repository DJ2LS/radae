#!/bin/bash -x
#
# Test ota_test.sh and check calibration of chirp based C/No estimation. Note C/No = P/No for chirp,
# as PAPR is zero.
#
# test usage:
#
#   ~/radae main $ ./test/ota_test_cal.sh ~/codec2-dev/build_linux/ -20

if [ $# -lt 2 ]; then
  echo "usage: $0 /path/to/codec2-dev/build No [ch options]"
  exit 1
fi

CODEC2_DEV_BUILD_DIR=$1
No=$2
shift; shift;
GAIN=0.25 # allow some headroom for noise and fading to prevent clipping

source test/make_g_mpp.sh
cp -f g_mpp.f32 fast_fading_samples.float

# Generate tx file and add noise
./ota_test.sh -x wav/brian_g8sez.wav --peak
${CODEC2_DEV_BUILD_DIR}/src/ch tx.wav - --gain ${GAIN} --No ${No} --after_fade --fading_dir . $@ | sox -t .s16 -r 8000 -c 1 - rx.wav

# run chirp only through 'ch' to get reference estimate of C/No
ch_log=$(mktemp)
sox tx.wav -t .s16 - trim 0 4 | \
~/codec2-dev/build_linux/src/ch - /dev/null --gain ${GAIN} --No ${No} --after_fade --fading_dir . $@ 2>${ch_log}

# Run Rx and check ML "loss" is OK, we don't check acq time as start time of RADAE is uncertain due to silence etc
rm -f features_rx_out.f32
rx_log=$(mktemp)
./ota_test.sh -r rx.wav >${rx_log}
python3 loss.py features_in.f32 features_rx_out.f32 --loss_test 0.3

# Check C/No estimates close
CNodB_ch=$(cat ${ch_log} | grep "C/No" | tr -s ' ' | cut -d' ' -f5)
CNodB_est=$(cat ${rx_log} | grep "Measured:" | tr -s ' ' | cut -d' ' -f2)
python3 -c "if abs(${CNodB_ch}-${CNodB_est}) < 1.0: print('CNodB PASS')"
cat ${rx_log} | grep "Measured:"