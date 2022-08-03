// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "../common/Core.sol";
import "../common/IRAI20Factory.sol";
import "../common/IRAI721Factory.sol";
import "../common/IValidatorManager.sol";

contract Goerli is Core {
    function initialize(
        IValidatorManager validatorManager,
        IRAI20Factory rai20Factory,
        IRAI721Factory rai721Factory
    ) external initializer {
        if (block.chainid != 5) revert ChainIdMismatch();
        __Core_init(validatorManager, rai20Factory, rai721Factory);
    }

    function normalizedChainId() public view virtual override returns (uint32) {
        return 10033;
    }
}
