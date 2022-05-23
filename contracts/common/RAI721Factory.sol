// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract RAI721 is ERC721, ERC721Enumerable {
    uint32 public immutable originalChainId;
    address public immutable originalContract;
    address public immutable coreContract;

    string public originalChain;
    string private _name;
    string private _symbol;

    constructor() ERC721("", "") {
        (_name, _symbol, originalChain, originalChainId, originalContract, coreContract) = RAI721Factory(_msgSender())
            .parameters();
    }

    modifier onlyCoreContract() {
        require(coreContract == _msgSender(), "Not from core");
        _;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 tokenId) external onlyCoreContract {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyCoreContract {
        require(ownerOf(tokenId) == _msgSender(), "Not owned");
        _burn(tokenId);
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

contract RAI721Factory {
    address public immutable deployer;
    address public coreContract;

    modifier onlyCoreContract() {
        require(msg.sender == coreContract, "Not core contract");
        _;
    }

    constructor() {
        deployer = msg.sender;
    }

    event CoreContractSet(address);

    function setCoreContract(address core) external {
        require(msg.sender == deployer, "Not deployer");
        require(coreContract == address(0), "Already set");
        coreContract = core;
        emit CoreContractSet(coreContract);
    }

    struct Parameters {
        string name;
        string symbol;
        string originalChain;
        uint32 originalChainId;
        address originalContract;
        address coreContract;
    }
    Parameters public parameters;

    event TokenCreated(address);

    function create(
        string memory name,
        string memory symbol,
        string memory originalChain,
        uint32 originalChainId,
        address originalContract
    ) public onlyCoreContract returns (address addr) {
        parameters = Parameters({
            name: name,
            symbol: symbol,
            originalChain: originalChain,
            originalChainId: originalChainId,
            originalContract: originalContract,
            coreContract: coreContract
        });
        addr = address(new RAI721{salt: calcSalt(originalChainId, originalContract)}());
        require(addr != address(0), "Create token failed");
        delete parameters;
        emit TokenCreated(addr);
        return addr;
    }

    function calcSalt(uint32 originalChainId, address originalContract) public pure returns (bytes32) {
        return keccak256(abi.encode(originalChainId, originalContract));
    }
}

contract FactoryHelper {
    //solhint-disable-next-line var-name-mixedcase
    bytes32 public immutable TOKEN_INIT_CODE_HASH = keccak256(abi.encodePacked(type(RAI721).creationCode));

    function calcAddress(
        address factory,
        uint32 originalChainId,
        address originalContract
    ) public view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                factory,
                                keccak256(abi.encode(originalChainId, originalContract)),
                                TOKEN_INIT_CODE_HASH
                            )
                        )
                    )
                )
            );
    }
}
