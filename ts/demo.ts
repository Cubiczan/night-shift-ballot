/**
 * Night Shift Ballot — local demo
 *
 * 1. Builds 38 Semaphore V4 identities (nurses).
 * 2. Registers only their commitments (secrets stay local).
 * 3. Generates real ZK proofs with semaphore-protocol/core.
 * 4. Verifies each proof off-chain.
 * 5. Optionally submits via a shared relayer wallet on Anvil so
 *    no nurse wallet ever appears on chain.
 *
 * Usage:
 *   npx tsx ts/demo.ts              # off-chain only
 *   npx tsx ts/demo.ts --anvil      # also talk to local Anvil (see scripts/run-demo.sh)
 */
import { Identity, Group, generateProof, verifyProof } from "@semaphore-protocol/core";
import { createWalletClient, createPublicClient, http, defineChain, getContract, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const CHOICE = { YES: 1n, NO: 2n, ABSTAIN: 3n } as const;
const SCOPE_SEED = "ballot:unsafe-staffing-2026-11-05";
const NURSE_COUNT = 38;
const useAnvil = process.argv.includes("--anvil");

function scopeFromSeed(seed: string): bigint {
  // Matches keccak256(abi.encodePacked(seed))? Solidity uses keccak256("...") for a string literal
  // which is keccak256 of the raw bytes. Use the same via viem keccak in anvil path;
  // for off-chain-only we just need a stable bigint — compute via TextEncoder + a tiny keccak.
  // Hard-code the Foundry value by reading from a fixture if present; else derive with viem.
  return 0n; // filled below once viem keccak is available
}

async function main() {
  const { keccak256, toBytes, stringToHex } = await import("viem");
  const ballotScope = BigInt(keccak256(stringToHex(SCOPE_SEED)));

  console.log("=== Night Shift Ballot demo ===");
  console.log("scope seed:", SCOPE_SEED);
  console.log("ballotScope:", ballotScope.toString());
  console.log("nurses:", NURSE_COUNT);

  // Each nurse creates an identity on their own device. We simulate that here.
  const nurses = Array.from({ length: NURSE_COUNT }, (_, i) => {
    const id = new Identity();
    return { index: i + 1, identity: id, commitment: id.commitment };
  });

  // Priya only ever sees commitments.
  const commitments = nurses.map((n) => n.commitment);
  const group = new Group(commitments);
  console.log("group root:", group.root.toString());
  console.log("group size:", group.size);

  // 5 nurses vote: 3 yes, 1 no, 1 abstain. The other 33 stay silent.
  const planned: { index: number; choice: bigint; label: string }[] = [
    { index: 0, choice: CHOICE.YES, label: "YES" },
    { index: 1, choice: CHOICE.YES, label: "YES" },
    { index: 2, choice: CHOICE.YES, label: "YES" },
    { index: 3, choice: CHOICE.NO, label: "NO" },
    { index: 4, choice: CHOICE.ABSTAIN, label: "ABSTAIN" },
  ];

  const votes: {
    nurseIndex: number;
    label: string;
    nullifier: string;
    verified: boolean;
    proof: Awaited<ReturnType<typeof generateProof>>;
  }[] = [];

  for (const p of planned) {
    const nurse = nurses[p.index];
    const proof = await generateProof(nurse.identity, group, p.choice, ballotScope);
    const ok = await verifyProof(proof);
    console.log(
      `nurse#${nurse.index} voted ${p.label}: nullifier=${proof.nullifier.toString().slice(0, 18)}… zk=${ok}`
    );
    votes.push({
      nurseIndex: nurse.index,
      label: p.label,
      nullifier: proof.nullifier.toString(),
      verified: ok,
      proof,
    });
  }

  // Double-vote attempt with the same identity+scope must produce the SAME nullifier.
  const dup = await generateProof(nurses[0].identity, group, CHOICE.NO, ballotScope);
  console.log(
    "double-vote nullifier equals first?",
    dup.nullifier === votes[0].proof.nullifier,
    "(Semaphore nullifier is unique per identity×scope — contract rejects the replay)"
  );

  const tally = { yes: 0, no: 0, abstain: 0 };
  for (const v of votes) {
    if (v.label === "YES") tally.yes++;
    else if (v.label === "NO") tally.no++;
    else tally.abstain++;
  }
  console.log("off-chain tally:", tally, "total", votes.length);
  console.log(
    "privacy check: commitments published =",
    commitments.length,
    "; vote events carry nullifier+choice only — no commitment, no nurse index."
  );

  mkdirSync("docs", { recursive: true });
  writeFileSync(
    "docs/demo-run.json",
    JSON.stringify(
      {
        ballotScope: ballotScope.toString(),
        groupRoot: group.root.toString(),
        memberCount: commitments.length,
        votes: votes.map(({ nurseIndex, label, nullifier, verified }) => ({
          // Deliberately omit nurseIndex from the "on-chain shaped" record below;
          // kept here only so the demo transcript is auditable.
          _demoOnlyNurseIndex: nurseIndex,
          label,
          nullifier,
          verified,
        })),
        tally,
        doubleVoteNullifierMatches: dup.nullifier === votes[0].proof.nullifier,
      },
      null,
      2
    )
  );
  console.log("wrote docs/demo-run.json");

  if (!useAnvil) {
    console.log("\nDone (off-chain). Re-run with --anvil after scripts/run-demo.sh starts Anvil.");
    return;
  }

  // --- Anvil path ----------------------------------------------------------
  const anvil = defineChain({
    id: 31337,
    name: "Anvil",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
  });
  // Anvil default accounts
  const priyaKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as Hex; // #0
  const relayerKey = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as Hex; // #1
  const priya = privateKeyToAccount(priyaKey);
  const relayer = privateKeyToAccount(relayerKey);

  const publicClient = createPublicClient({ chain: anvil, transport: http() });
  const priyaWallet = createWalletClient({ account: priya, chain: anvil, transport: http() });
  const relayerWallet = createWalletClient({ account: relayer, chain: anvil, transport: http() });

  const deployed = JSON.parse(readFileSync("docs/local-deploy.json", "utf8")) as {
    semaphore: Hex;
    ballot: Hex;
    abi: any;
  };

  const ballot = getContract({
    address: deployed.ballot,
    abi: deployed.abi,
    client: { public: publicClient, wallet: priyaWallet },
  });

  // Register all 38 commitments as Priya (registrar).
  console.log("registering 38 commitments on-chain as Priya…");
  const txReg = await (ballot as any).write.registerMany([commitments], { account: priya });
  await publicClient.waitForTransactionReceipt({ hash: txReg });
  console.log("registered. tx:", txReg);

  // Relayer submits each proof — nurse keys never touch the chain.
  for (const v of votes) {
    const p = v.proof;
    const proofTuple = {
      merkleTreeDepth: BigInt(p.merkleTreeDepth),
      merkleTreeRoot: BigInt(p.merkleTreeRoot),
      nullifier: BigInt(p.nullifier),
      message: BigInt(p.message),
      scope: BigInt(p.scope),
      points: p.points.map((x: bigint | string) => BigInt(x)) as [
        bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint
      ],
    };
    const hash = await relayerWallet.writeContract({
      address: deployed.ballot,
      abi: deployed.abi,
      functionName: "vote",
      args: [proofTuple],
      account: relayer,
      chain: anvil,
    });
    await publicClient.waitForTransactionReceipt({ hash });
    console.log(`relayer submitted ${v.label}; nullifier…${v.nullifier.slice(0, 12)}; tx ${hash}`);
  }

  const onchain = (await publicClient.readContract({
    address: deployed.ballot,
    abi: deployed.abi,
    functionName: "tally",
  })) as readonly [bigint, bigint, bigint, bigint, boolean];
  console.log("on-chain tally:", {
    yes: Number(onchain[0]),
    no: Number(onchain[1]),
    abstain: Number(onchain[2]),
    total: Number(onchain[3]),
    closed: onchain[4],
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
