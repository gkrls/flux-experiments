#!/usr/bin/env bash
set -euo pipefail

FLUX_HOME="$HOME/flux"
FLUX_REPO="https://github.com/gkrls/flux.git"
FLUX_BRANCH="wip"
TEST_HOME="$HOME/flux-experiments"
TEST_REPO="https://github.com/gkrls/flux-experiments.git"
TEST_BRANCH="wip"

NEED_BUILD=0

# Clone on the first run
[[ -d "$FLUX_HOME/.git" ]] || git clone -b "$FLUX_BRANCH" "$FLUX_REPO" "$FLUX_HOME"
[[ -d "$TEST_HOME/.git" ]] || git clone -b "$TEST_BRANCH" "$TEST_REPO" "$TEST_HOME"

# Create venv on first run, or just activate it otherwise
if [[ ! -d "$TEST_HOME/venv" ]]; then
    python3 -m venv "$TEST_HOME/venv"
    source "$TEST_HOME/venv/bin/activate"
    pip install -r "$FLUX_HOME/src/dpa_torch_plugin/requirements.txt"
    pip install -r "$TEST_HOME/requirements-remote.txt"
    NEED_BUILD=1
else
    source "$TEST_HOME/venv/bin/activate"
fi

# If needed and resync the repos recompile 
if [[ $# -eq 1 && "$1" == "sync" ]]; then
  git -C "$FLUX_HOME" fetch -q origin || true
  git -C "$FLUX_HOME" checkout "$FLUX_BRANCH" 2>/dev/null || true
  git -C "$FLUX_HOME" reset --hard origin/"$FLUX_BRANCH" 2>/dev/null || true #git -C "$DIR" reset --hard || true
  git -C "$FLUX_HOME" pull --ff-only origin "$FLUX_BRANCH" 2>/dev/null || true
  git -C "$FLUX_HOME" clean -ffd || true

  git -C "$TEST_HOME" reset --hard >/dev/null 2>&1 || true
  git -C "$TEST_HOME" pull --ff-only || true
  NEED_BUILD=1
fi

# Build if first run or sync
if [[ "$NEED_BUILD" -eq 1 ]]; then
    mkdir -p "$FLUX_HOME/build"
    cd "$FLUX_HOME/build"
    cmake -DCMAKE_INSTALL_MESSAGE=LAZY \
          -DCMAKE_BUILD_TYPE=Release \
          -DDPA_TRACE=OFF \
          -DDPA_DEVELOP=OFF \
          -DDPA_SWITCH=OFF \
          -DDPA_AVX=ON \
          -DDPA_PROFILE=OFF \
          -DDPA_DPDK_RX_REUSE=ON \
          -DDPA_DPDK_WIN_HUGE=ON \
          -DDPA_TORCH_PINNEDPOOL=ON ..
    make -j4 torch-plugin
fi

cd $TEST_HOME

IFACE="${IFACE:-ens4f1}" 
# Derive IP on IFACE, rank = last octet - 1
IP=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1 || true)
if [[ -z "${IP}" ]]; then
  echo "ERROR: could not get IPv4 for IFACE=$IFACE" >&2
  exit 1
fi
RANK=$(( ${IP##*.} - 1 ))
WORLD="${WORLD:-6}"
MASTER_ADDR="${MASTER_ADDR:-"42.0.1.1"}"
MASTER_PORT="${MASTER_PORT:-"29500"}"
PROG=$TEST_HOME/experiments/allreduce/allreduce.py
CONF=$TEST_HOME/configs/edgecore.json

VALGRIND=valgrind #--leak-check=full --show-leak-kinds=all --track-origins=yes"
NSYS="nsys profile -w true -t cuda,nvtx,osrt,cudnn,cublas --cuda-memory-usage=true --sampling-period=200000 -d 30 -o $HOME/nsys_profile -f true"
PERF="perf stat -d --" # perf stat -e cache-misses,cache-references
GDB="gdb --args"

# NCCL STUFF
export NCCL_SOCKET_IFNAME=$IFACE
export NCCL_IB_HCA=mlx5_1
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=NET

# GDR  # export NCCL_IB_PCI_RELAXED_ORDERING=1
export NCCL_NET_GDR_LEVEL=SYS  # Tell NCCL that crossing the internal CPU fabric (SYS level) is okay
export NCCL_P2P_LEVEL=SYS
export NCCL_P2P_DISABLE=0      # Ensure Peer-to-Peer is not restricted
export NCCL_IB_GDR_FLUSH=1     # Recommended for Mellanox + GDR performance


# export NCCL_PROTO=LL           # LL, LL128, Simple
export NCCL_ALGO=Ring
export NCCL_MIN_NCHANNELS=8


sudo modprobe nvidia_peermem 2>/dev/null || true

# INPUT SIZES
XXXXXXXS=25000  # 0.10MB
XXXXXXS=62500   # 0.25MB
XXXXXS=125000   # 0.50MB
XXXXS=250000    # 1MB
XXXS=625000     # 2.5MB
XXS=1250000     # 5.0MB
XS=2500000      # 10MB
S=6250000       # 25MB
M=12500000      # 50MB
L=25000000      # 100MB
XL=50000000     # 200MB
XXL=75000000    # 300ΜΒ
XXXL=100000000  # 400MB
XXXXL=125000000 # 500MB

# DPA STUFF
export DPA_PREEMPTIVE=0
export DPA_TORCH_MODE=worksteal
export DPA_TORCH_PIPELINE_CHUNKS=4

WIN_T2=192
WIN_T4=96
WIN_T6=64
WIN_L6=128
WIN_L8=64

# export DPA_SYN_DISABLE=0
# export DPA_DPDK_MONITOR=0
# export DPA_DPDK_MONITOR_INTERVAL_US=500

echo "[ALLREDUCE BENCHMARK]"
sudo -E DPA_LOG=Info DPA_SCHEDULER=OFF $(which python) $PROG \
  --rank $RANK --world_size $WORLD --master_addr $MASTER_ADDR --master_port $MASTER_PORT \
  -d cuda -t float32 -s $L -w 5 -i 20 --pattern 3 --batch \
  -b dpa_dpdk --dpa_conf $CONF --dpa_pipes 4 --dpa_window 96 --dpa_threads 6 \
  --dpa_k 6
  #--dpa_timeout_us 60 --dpa_timeout_init_scaling 20 \
  # --gloo_socket_ifname $IFACE
  # --straggle_rank 1 --straggle_ms 200 --straggle_num 10 --straggle_start 0 --straggle_mode op
  
  # --dpa_k 5 --dpa_preemptive --dpa_window 64 --dpa_threads 6 --dpa_timeout_us 100 --dpa_profile_skip 4 --dpa_timeout_init_scaling 5 --batch
 
  # --gloo_socket_ifname $IFACE --gloo_num_threads 2
  # --nccl_socket_nthreads 6 --nccl_nsocks_perthread 2
  # --pattern 1 --nccl_ib_qps_per_connection 1
