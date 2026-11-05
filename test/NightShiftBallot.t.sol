// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {NightShiftBallot} from "../src/NightShiftBallot.sol";
import {MockSemaphore} from "../src/mocks/MockSemaphore.sol";
import {ISemaphore} from "../src/interfaces/ISemaphore.sol";

contract NightShiftBallotTest is Test {
    MockSemaphore internal sem;
    NightShiftBallot internal ballot;
    address internal priya;
    address internal relayer;
    address internal nurseWallet;
    uint256 internal scope;

    function setUp() public {
        priya = makeAddr("priya");
        relayer = makeAddr("relayer");
        nurseWallet = makeAddr("nurseWallet");
        scope = uint256(keccak256("ballot:unsafe-staffing-2026-11-05"));
        sem = new MockSemaphore();
        ballot = new NightShiftBallot(
            ISemaphore(address(sem)),
            priya,
            block.timestamp + 1 days,
            38,
            scope
        );
    }

    function _proof(uint256 nullifier, uint256 message) internal view returns (ISemaphore.SemaphoreProof memory p) {
        p.merkleTreeDepth = 1;
        p.merkleTreeRoot = uint256(keccak256("root"));
        p.nullifier = nullifier;
        p.message = message;
        p.scope = scope;
    }

    function test_register_only_registrar() public {
        vm.expectRevert(NightShiftBallot.OnlyRegistrar.selector);
        ballot.register(123);

        vm.prank(priya);
        ballot.register(123);
        assertEq(ballot.memberCount(), 1);
    }

    function test_max_38_members() public {
        vm.startPrank(priya);
        for (uint256 i = 1; i <= 38; i++) {
            ballot.register(i);
        }
        vm.expectRevert(NightShiftBallot.TooManyMembers.selector);
        ballot.register(39);
        vm.stopPrank();
        assertEq(ballot.memberCount(), 38);
    }

    function test_vote_counts_choice_and_hides_nurse_wallet() public {
        vm.prank(priya);
        ballot.register(111);

        vm.prank(relayer);
        ballot.vote(_proof(9001, 1));

        (uint256 y, uint256 n, uint256 a, uint256 t, bool closed) = ballot.tally();
        assertEq(y, 1);
        assertEq(n, 0);
        assertEq(a, 0);
        assertEq(t, 1);
        assertFalse(closed);
    }

    function test_double_vote_blocked_by_nullifier() public {
        vm.prank(priya);
        ballot.register(111);

        vm.prank(relayer);
        ballot.vote(_proof(9001, 1));

        vm.prank(relayer);
        vm.expectRevert();
        ballot.vote(_proof(9001, 2));
    }

    function test_scope_must_match_ballot() public {
        vm.prank(priya);
        ballot.register(111);

        ISemaphore.SemaphoreProof memory p = _proof(9001, 1);
        p.scope = 999;
        vm.prank(relayer);
        vm.expectRevert(NightShiftBallot.ScopeMismatch.selector);
        ballot.vote(p);
    }

    function test_bad_choice_rejected() public {
        vm.prank(priya);
        ballot.register(111);

        vm.prank(relayer);
        vm.expectRevert(NightShiftBallot.BadChoice.selector);
        ballot.vote(_proof(9001, 99));
    }

    function test_closes_at_enforced() public {
        vm.prank(priya);
        ballot.register(111);

        vm.warp(block.timestamp + 2 days);
        vm.prank(relayer);
        vm.expectRevert(NightShiftBallot.BallotClosedErr.selector);
        ballot.vote(_proof(9001, 1));
    }

    function test_full_tally_yes_no_abstain() public {
        vm.startPrank(priya);
        ballot.register(1);
        ballot.register(2);
        ballot.register(3);
        vm.stopPrank();

        vm.startPrank(relayer);
        ballot.vote(_proof(1, 1));
        ballot.vote(_proof(2, 2));
        ballot.vote(_proof(3, 3));
        vm.stopPrank();

        (uint256 y, uint256 n, uint256 a, uint256 t,) = ballot.tally();
        assertEq(y, 1);
        assertEq(n, 1);
        assertEq(a, 1);
        assertEq(t, 3);

        vm.prank(makeAddr("wardClerk"));
        (y,,,,) = ballot.tally();
        assertEq(y, 1);
    }

    function test_nurse_wallet_not_required() public {
        vm.prank(priya);
        ballot.register(42);
        vm.prank(relayer);
        ballot.vote(_proof(7, 1));
        assertEq(nurseWallet.balance, 0);
    }
}
