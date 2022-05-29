// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./Component.sol";

contract RAI721 is ERC721, ERC721Enumerable {
    uint32 private immutable _originalChainId;
    bytes32 private immutable _originalContract;
    address private immutable _coreContract;

    string private _originalChain;
    string private _name;
    string private _symbol;

    constructor() ERC721("", "") {
        RAI721Factory.Parameters memory p = RAI721Factory(_msgSender()).parameters();
        _name = p.name;
        _symbol = p.symbol;
        _originalChain = p.originalChain;
        _originalChainId = p.originalChainId;
        _originalContract = p.originalContract;
        _coreContract = p.coreContract;
    }

    modifier onlyCoreContract() {
        require(_coreContract == _msgSender(), "Not from core");
        _;
    }

    function mint(address to, uint256 tokenId) external onlyCoreContract {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyCoreContract {
        require(ownerOf(tokenId) == _msgSender(), "Not owned");
        _burn(tokenId);
    }

    function originalChain() external view returns (string memory) {
        return _originalChain;
    }

    function originalChainId() external view returns (uint32) {
        return _originalChainId;
    }

    function originalContract() external view returns (bytes32) {
        return _originalContract;
    }

    function coreContract() external view returns (address) {
        return _coreContract;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

contract RAI721Factory is Component {
    struct Parameters {
        string name;
        string symbol;
        string originalChain;
        uint32 originalChainId;
        bytes32 originalContract;
        address coreContract;
    }

    event TokenCreated(address);

    Parameters private _parameters;

    function create(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract
    ) external onlyCoreContract returns (address addr) {
        _parameters = Parameters({
            name: name,
            symbol: symbol,
            originalChain: originalChain,
            originalChainId: originalChainId,
            originalContract: originalContract,
            coreContract: coreContract()
        });
        addr = address(new RAI721{salt: calcSalt(originalChainId, originalContract)}());
        require(addr != address(0), "Create token failed");
        delete _parameters;
        emit TokenCreated(addr);
        return addr;
    }

    function parameters () external view returns (Parameters memory) {
        return _parameters;
    }

    function calcSalt(uint32 originalChainId, bytes32 originalContract)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(originalChainId, originalContract));
    }
}

contract FactoryHelper {
    //solhint-disable-next-line var-name-mixedcase
    bytes32 public immutable TOKEN_INIT_CODE_HASH =
        keccak256(abi.encodePacked(type(RAI721).creationCode));

    function calcAddress(
        address factory,
        uint32 originalChainId,
        bytes32 originalContract
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
