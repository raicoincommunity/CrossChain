// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IRAI20 {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function originalChain() external view returns (string memory);
    function originalChainId() external view returns (uint32);
    function originalContract() external view returns (bytes32);
    function coreContract() external view returns (address);
}

interface IRAI20Factory {
    function create(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract,
        uint8 decimals
    ) external returns (address addr);
}
