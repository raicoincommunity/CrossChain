// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./BSCTestV2.sol";

contract BSCTestV3 is BSCTestV2 {
    address public constant newVerifierV3 = 0x4f428DD655246e5e5a30e7853D6F575D7eE74449;

    function initializeV3() external reinitializer(3) {
        if (block.chainid != 97) revert ChainIdMismatch();
        __Verifier_init(IValidatorManager(newVerifierV3));
    }
}
