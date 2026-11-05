// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {NightShiftBallot} from "../src/NightShiftBallot.sol";
import {MockSemaphore} from "../src/mocks/MockSemaphore.sol";
import {ISemaphore} from "../src/interfaces/ISemaphore.sol";

contract DeployLocal is Script {
    function run() external {
        uint256 scope = uint256(keccak256("ballot:unsafe-staffing-2026-11-05"));
        uint256 closesIn = vm.envOr("CLOSES_IN", uint256(2 hours));

        vm.startBroadcast();
        address registrar = msg.sender; // Anvil account #0 when using its key
        MockSemaphore sem = new MockSemaphore();
        NightShiftBallot ballot = new NightShiftBallot(
            ISemaphore(address(sem)),
            registrar,
            block.timestamp + closesIn,
            38,
            scope
        );
        vm.stopBroadcast();

        console2.log("MockSemaphore", address(sem));
        console2.log("NightShiftBallot", address(ballot));
        console2.log("groupId", ballot.groupId());
        console2.log("ballotScope", ballot.ballotScope());
        console2.log("closesAt", ballot.closesAt());
        console2.log("registrar", ballot.registrar());
    }
}
