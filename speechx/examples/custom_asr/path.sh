# This contains the locations of binarys build required for running the examples.

MAIN_ROOT=`realpath $PWD/../../../`
SPEECHX_ROOT=`realpath $MAIN_ROOT/speechx`
SPEECHX_LIB_ROOT=$SPEECHX_ROOT/examples/custom_asr/resource
SPEECHX_EXAMPLES=$SPEECHX_ROOT/build/examples

export LC_AL=C

# srilm
export LIBLBFGS=${MAIN_ROOT}/tools/liblbfgs-1.10
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:${LIBLBFGS}/lib/.libs:${SPEECHX_LIB_ROOT}/lib
export SRILM=${MAIN_ROOT}/tools/srilm

# kaldi lm
KALDI_DIR=$SPEECHX_ROOT/build/speechx/kaldi/
OPENFST_DIR=$SPEECHX_ROOT/fc_patch/openfst-build/src
export PATH=${PATH}:${SRILM}/bin:${SRILM}/bin/i686-m64:$KALDI_DIR/lmbin:$KALDI_DIR/fstbin:$OPENFST_DIR/bin:$SPEECHX_EXAMPLES/ds2_ol/decoder
