// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./BSCTest.sol";

contract BSCTestV2 is BSCTest {
    address public constant newVerifier = 0xD1dC4FA7EEF2B1B7baFC82DdF8105eaEB5E19f80;

    function initializeV2() external reinitializer(2) {
        if (block.chainid != 97) revert ChainIdMismatch();
        __Verifier_init(IValidatorManager(newVerifier));
    }
}
