// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Subset of Semaphore V4's ISemaphore used by NightShiftBallot.
/// @dev Full interface: semaphore-protocol/contracts. On Sepolia the live
///      Semaphore is at 0xC10E5102A2Cc077BE3B9740Fc0Ad7e27Ff8E0245.
interface ISemaphore {
    struct SemaphoreProof {
        uint256 merkleTreeDepth;
        uint256 merkleTreeRoot;
        uint256 nullifier;
        uint256 message;
        uint256 scope;
        uint256[8] points;
    }

    function createGroup() external returns (uint256 groupId);
    function createGroup(address admin) external returns (uint256 groupId);
    function addMember(uint256 groupId, uint256 identityCommitment) external;
    function addMembers(uint256 groupId, uint256[] calldata identityCommitments) external;
    function validateProof(uint256 groupId, SemaphoreProof calldata proof) external;
    function verifyProof(uint256 groupId, SemaphoreProof calldata proof) external view returns (bool);
}
