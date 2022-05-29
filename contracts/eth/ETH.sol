// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../common/Core.sol";
import "../common/IRAI20Factory.sol";
import "../common/IRAI721Factory.sol";
import "../common/IValidatorManager.sol";

contract ETH is Core {
    function initialize(
        IValidatorManager validatorManager,
        IRAI20Factory rai20Factory,
        IRAI721Factory rai721Factory
    ) external initializer {
        __Core_init(validatorManager, rai20Factory, rai721Factory);
    }

    function normalizedChainId() public view virtual override returns (uint32) {
        return 3;
    }
}
