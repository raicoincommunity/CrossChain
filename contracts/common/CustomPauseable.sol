// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./CustomEIP712Upgradeable.sol";
import "./NonceManager.sol";
import "./Verifier.sol";

contract CustomPausable is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    CustomEIP712Upgradeable,
    NonceManager,
    Verifier
{
    bytes32 private constant _PAUSE_TYPEHASH = keccak256("Pause(uint256 nonce)");
    bytes32 private constant _UNPAUSE_TYPEHASH = keccak256("Unpause(uint256 nonce)");

    function pause(uint256 nonce, bytes calldata signatures)
        external
        nonReentrant
        whenNotPaused
        useNonce(nonce)
    {
        bytes32 structHash = keccak256(abi.encode(_PAUSE_TYPEHASH, nonce));
        require(verify(structHash, signatures), "verify");

        _pause();
    }

    function unpause(uint256 nonce, bytes calldata signatures)
        external
        nonReentrant
        whenPaused
        useNonce(nonce)
    {
        bytes32 structHash = keccak256(abi.encode(_UNPAUSE_TYPEHASH, nonce));
        require(verify(structHash, signatures), "verify");

        _unpause();
    }
}
