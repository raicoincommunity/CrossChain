// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./errors.sol";

contract NonceManager is Initializable {
    uint256 private _nonce;

    modifier useNonce(uint256 nonce) {
        if (nonce != _nonce) revert NonceMismatch();
        nonce++;
        _;
    }
}
