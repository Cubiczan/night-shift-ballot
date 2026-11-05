// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISemaphore} from "../interfaces/ISemaphore.sol";

/// @title MockSemaphore
/// @notice Local stand-in for Semaphore V4 (Foundry + Anvil demos).
/// @dev Honesty note — this mock:
///      * DOES enforce one-nullifier-per-group (double-vote stop)
///      * DOES enforce group-admin for addMember / addMembers
///      * does NOT verify Groth16 points
///      * does NOT recompute the LeanIMT Merkle root
///      Off-chain, `ts/demo.ts` builds real Semaphore V4 proofs with
///      `semaphore-protocol/core` and calls `verifyProof` before the
///      relayer submits. Against Sepolia, point NightShiftBallot at the
///      live Semaphore (`0xC10E5102A2Cc077BE3B9740Fc0Ad7e27Ff8E0245`)
///      and both checks become real.
contract MockSemaphore is ISemaphore {
    uint256 public groupCounter;

    struct Group {
        address admin;
        mapping(uint256 => bool) nullifiers;
        uint256 memberCount;
    }

    mapping(uint256 => Group) private groups;

    event GroupCreated(uint256 indexed groupId, address indexed admin);
    event MemberAdded(uint256 indexed groupId, uint256 identityCommitment, uint256 size);
    event ProofValidated(
        uint256 indexed groupId,
        uint256 merkleTreeDepth,
        uint256 merkleTreeRoot,
        uint256 nullifier,
        uint256 message,
        uint256 scope
    );

    error NotAdmin();
    error NullifierAlreadyUsed();
    error BadDepth();

    function createGroup() external returns (uint256 groupId) {
        return _create(msg.sender);
    }

    function createGroup(address admin) external returns (uint256 groupId) {
        return _create(admin);
    }

    function _create(address admin) internal returns (uint256 groupId) {
        groupId = groupCounter++;
        groups[groupId].admin = admin;
        emit GroupCreated(groupId, admin);
    }

    function addMember(uint256 groupId, uint256 identityCommitment) external {
        if (msg.sender != groups[groupId].admin) revert NotAdmin();
        groups[groupId].memberCount += 1;
        emit MemberAdded(groupId, identityCommitment, groups[groupId].memberCount);
    }

    function addMembers(uint256 groupId, uint256[] calldata identityCommitments) external {
        if (msg.sender != groups[groupId].admin) revert NotAdmin();
        for (uint256 i = 0; i < identityCommitments.length; i++) {
            groups[groupId].memberCount += 1;
            emit MemberAdded(groupId, identityCommitments[i], groups[groupId].memberCount);
        }
    }

    function memberCountOf(uint256 groupId) external view returns (uint256) {
        return groups[groupId].memberCount;
    }

    function validateProof(uint256 groupId, SemaphoreProof calldata proof) external {
        if (proof.merkleTreeDepth < 1 || proof.merkleTreeDepth > 32) revert BadDepth();
        if (groups[groupId].nullifiers[proof.nullifier]) revert NullifierAlreadyUsed();
        groups[groupId].nullifiers[proof.nullifier] = true;
        emit ProofValidated(
            groupId, proof.merkleTreeDepth, proof.merkleTreeRoot, proof.nullifier, proof.message, proof.scope
        );
    }

    function verifyProof(uint256 /*groupId*/, SemaphoreProof calldata proof) external pure returns (bool) {
        return proof.merkleTreeDepth >= 1 && proof.merkleTreeDepth <= 32;
    }
}
