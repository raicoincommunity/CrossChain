// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IValidatorManager {
    function verifyTypedData(bytes32 typedHash, bytes calldata signatures) external view returns (bool);
}