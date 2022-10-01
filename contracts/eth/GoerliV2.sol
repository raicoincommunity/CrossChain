// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./Goerli.sol";

contract GoerliV2 is Goerli {
    address private constant _validatorManagerV2 = 0x770f53F87c417eEA44a8f1314A22962F40Be9cd4;

    function initializeV2() external reinitializer(2) {
        if (block.chainid != 5) revert ChainIdMismatch();
        __Verifier_init(IValidatorManager(_validatorManagerV2));
    }
}
