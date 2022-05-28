// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract NonceManager is Initializable {
    uint256 private _nonce;

    modifier useNonce(uint256 nonce) {
        require(nonce == _nonce, "nonce");
        nonce++;
        _;
    }
}
