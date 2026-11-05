#!/usr/bin/env bash
# Start Anvil, deploy MockSemaphore + NightShiftBallot, run the TS demo against it.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."

pkill -f 'anvil.*8545' 2>/dev/null || true
anvil --silent --port 8545 >/tmp/anvil-nsb.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
sleep 1

PRIYA=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
OUT=$(REGISTRY="$PRIYA" REGISTRAR="$PRIYA" forge script script/DeployLocal.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast 2>&1)
echo "$OUT" | tail -40

SEM=$(echo "$OUT" | awk '/MockSemaphore/ {print $2}' | tail -1)
BALLOT=$(echo "$OUT" | awk '/NightShiftBallot/ {print $2}' | tail -1)
echo "SEM=$SEM BALLOT=$BALLOT"

# Extract ABI
forge inspect NightShiftBallot abi > /tmp/nsb-abi.json
node --input-type=module <<NODE
import { writeFileSync } from "fs";
const abi = JSON.parse(await import("fs").then(m => m.readFileSync("/tmp/nsb-abi.json","utf8")));
writeFileSync("docs/local-deploy.json", JSON.stringify({
  semaphore: "$SEM",
  ballot: "$BALLOT",
  abi
}, null, 2));
console.log("wrote docs/local-deploy.json");
NODE

npx tsx ts/demo.ts --anvil
