// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

interface IRAI721 {
    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    function originalChain() external view returns (string memory);

    function originalChainId() external view returns (uint32);

    function originalContract() external view returns (bytes32);

    function coreContract() external view returns (address);
}

interface IRAI721Factory {
    function create(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract
    ) external returns (address addr);
}
