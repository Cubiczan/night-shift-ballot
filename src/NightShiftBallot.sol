// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISemaphore} from "./interfaces/ISemaphore.sol";

/// @title NightShiftBallot
/// @notice Anonymous staff vote for Priya's 38-nurse night shift.
/// @dev Built for Devcon 8 · Build Battle 3: "Count Every Vote, Name No Voter".
///
///      What Semaphore proves: group membership + one-nullifier-per-scope.
///      What THIS contract still must do (per the brief):
///        1. Pin the proof's `scope` to this ballot's id.
///        2. Enforce the closing time.
///        3. Count the choice carried in the proof's `message`.
///
///      Metadata: anyone (a shared ward relayer) can submit a voter's proof.
///      Nurses generate identities and proofs on their own devices; they never
///      need to send a transaction from a personal wallet, so chain metadata
///      does not name them.
contract NightShiftBallot {
    // Choices encoded in the Semaphore proof message.
    uint8 public constant CHOICE_YES = 1;
    uint8 public constant CHOICE_NO = 2;
    uint8 public constant CHOICE_ABSTAIN = 3;

    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;
    /// @notice Scope bound into every proof for this ballot. Equals the
    ///         on-chain ballot id so a proof for ballot A cannot be replayed on B.
    uint256 public immutable ballotScope;
    uint256 public immutable closesAt;
    address public immutable registrar; // Priya / shift lead — adds commitments only

    uint256 public yesCount;
    uint256 public noCount;
    uint256 public abstainCount;
    uint256 public totalVotes;

    mapping(uint256 => bool) public nullifierUsed; // defence in depth (Semaphore also tracks)

    event MemberRegistered(uint256 indexed identityCommitment, uint256 indexed index);
    event VoteCast(uint256 indexed nullifier, uint8 choice, address indexed submitter);
    event BallotClosed(uint256 yesCount, uint256 noCount, uint256 abstainCount, uint256 totalVotes);

    error OnlyRegistrar();
    error BallotClosedErr();
    error BallotStillOpen();
    error BadChoice();
    error ScopeMismatch();
    error NullifierReplay();
    error TooManyMembers();

    uint256 public memberCount;
    uint256 public immutable maxMembers;

    constructor(
        ISemaphore semaphore_,
        address registrar_,
        uint256 closesAt_,
        uint256 maxMembers_,
        uint256 ballotScope_
    ) {
        require(closesAt_ > block.timestamp, "closesAt in the past");
        require(maxMembers_ > 0 && maxMembers_ <= 256, "bad maxMembers");
        semaphore = semaphore_;
        registrar = registrar_;
        closesAt = closesAt_;
        maxMembers = maxMembers_;
        ballotScope = ballotScope_;
        // Ballot contract is the Semaphore group admin so only it can add members.
        groupId = semaphore_.createGroup(address(this));
    }

    modifier onlyRegistrar() {
        if (msg.sender != registrar) revert OnlyRegistrar();
        _;
    }

    /// @notice Priya registers a nurse's identity commitment (NOT the secret).
    ///         The nurse generates the Identity on their own device and shares
    ///         only the commitment. Secrets never leave the device.
    function register(uint256 identityCommitment) external onlyRegistrar {
        if (block.timestamp >= closesAt) revert BallotClosedErr();
        if (memberCount >= maxMembers) revert TooManyMembers();
        memberCount += 1;
        semaphore.addMember(groupId, identityCommitment);
        emit MemberRegistered(identityCommitment, memberCount);
    }

    function registerMany(uint256[] calldata identityCommitments) external onlyRegistrar {
        if (block.timestamp >= closesAt) revert BallotClosedErr();
        if (memberCount + identityCommitments.length > maxMembers) revert TooManyMembers();
        memberCount += identityCommitments.length;
        semaphore.addMembers(groupId, identityCommitments);
        for (uint256 i = 0; i < identityCommitments.length; i++) {
            emit MemberRegistered(identityCommitments[i], memberCount - identityCommitments.length + i + 1);
        }
    }

    /// @notice Cast an anonymous vote. Anyone may submit (the ward relayer).
    ///         The voter's wallet never has to appear on chain.
    function vote(ISemaphore.SemaphoreProof calldata proof) external {
        if (block.timestamp >= closesAt) revert BallotClosedErr();
        if (proof.scope != ballotScope) revert ScopeMismatch();

        uint8 choice = _asChoice(proof.message);
        if (nullifierUsed[proof.nullifier]) revert NullifierReplay();

        // Semaphore: membership + uniqueness for this scope. Reverts on bad proof
        // or a nullifier already used inside the group.
        semaphore.validateProof(groupId, proof);

        nullifierUsed[proof.nullifier] = true;
        totalVotes += 1;
        if (choice == CHOICE_YES) yesCount += 1;
        else if (choice == CHOICE_NO) noCount += 1;
        else abstainCount += 1;

        // Emit nullifier + choice + submitter (relayer). Never the voter's identity.
        emit VoteCast(proof.nullifier, choice, msg.sender);
    }

    function _asChoice(uint256 message) internal pure returns (uint8) {
        if (message == CHOICE_YES) return CHOICE_YES;
        if (message == CHOICE_NO) return CHOICE_NO;
        if (message == CHOICE_ABSTAIN) return CHOICE_ABSTAIN;
        revert BadChoice();
    }

    /// @notice Public tally. Anyone on the ward can check the result.
    function tally()
        external
        view
        returns (uint256 yes_, uint256 no_, uint256 abstain_, uint256 total_, bool closed_)
    {
        return (yesCount, noCount, abstainCount, totalVotes, block.timestamp >= closesAt);
    }

    function requireClosed() external view {
        if (block.timestamp < closesAt) revert BallotStillOpen();
    }
}
