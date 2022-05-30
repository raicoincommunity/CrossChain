// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Component.sol";
import "./errors.sol";

contract RAI20 is ERC20 {
    uint8 private immutable _decimals;
    uint32 private immutable _originalChainId;
    bytes32 private immutable _originalContract;
    address private immutable _coreContract;

    string private _originalChain;
    string private _name;
    string private _symbol;

    constructor() ERC20("", "") {
        RAI20Factory.Parameters memory p = RAI20Factory(_msgSender()).parameters();
        _name = p.name;
        _symbol = p.symbol;
        _originalChain = p.originalChain;
        _originalChainId = p.originalChainId;
        _originalContract = p.originalContract;
        _coreContract = p.coreContract;
        _decimals = p.decimals;
    }

    modifier onlyCoreContract() {
        if (_msgSender() != _coreContract) revert NotCalledByCoreContract();
        _;
    }

    function mint(address to, uint256 amount) external onlyCoreContract {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyCoreContract {
        _burn(_msgSender(), amount);
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

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract RAI20Factory is Component {
    struct Parameters {
        string name;
        string symbol;
        string originalChain;
        uint32 originalChainId;
        bytes32 originalContract;
        uint8 decimals;
        address coreContract;
    }

    Parameters private _parameters;

    event TokenCreated(address);

    function create(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract,
        uint8 decimals
    ) external onlyCoreContract returns (address addr) {
        _parameters = Parameters({
            name: name,
            symbol: symbol,
            originalChain: originalChain,
            originalChainId: originalChainId,
            originalContract: originalContract,
            decimals: decimals,
            coreContract: coreContract()
        });
        addr = address(new RAI20{salt: calcSalt(originalChainId, originalContract)}());
        if (addr == address(0)) revert CreateWrappedTokenFailed();
        delete _parameters;
        emit TokenCreated(addr);
        return addr;
    }

    function parameters() external view returns (Parameters memory) {
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
        keccak256(abi.encodePacked(type(RAI20).creationCode));

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
