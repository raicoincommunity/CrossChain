// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RAI20 is ERC20 {
    uint8 private immutable _decimals;
    uint32 public immutable originalChainId;
    address public immutable originalContract;
    address public immutable coreContract;

    string public originalChain;
    string private _name;
    string private _symbol;

    constructor() ERC20("", "") {
        (
            _name,
            _symbol,
            originalChain,
            originalChainId,
            originalContract,
            _decimals,
            coreContract
        ) = RAI20Factory(_msgSender()).parameters();
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

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyCoreContract {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyCoreContract {
        _burn(_msgSender(), amount);
    }
}

contract RAI20Factory {
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
        uint8 decimals;
        address coreContract;
    }
    Parameters public parameters;

    event TokenCreated(address);

    function create(
        string memory name,
        string memory symbol,
        string memory originalChain,
        uint32 originalChainId,
        address originalContract,
        uint8 decimals
    ) public onlyCoreContract returns (address addr) {
        parameters = Parameters({
            name: name,
            symbol: symbol,
            originalChain: originalChain,
            originalChainId: originalChainId,
            originalContract: originalContract,
            decimals: decimals,
            coreContract: coreContract
        });
        addr = address(
            new RAI20{salt: calcSalt(originalChainId, originalContract)}()
        );
        require(addr != address(0), "RAI20Factory: create token failed");
        delete parameters;
        emit TokenCreated(addr);
        return addr;
    }

    function calcSalt(uint32 originalChainId, address originalContract)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(originalChainId, originalContract));
    }
}

contract FactoryHelper {
    bytes32 public immutable TOKEN_INIT_CODE_HASH =
        keccak256(abi.encodePacked(type(RAI20).creationCode));

    function calcAddress(address factory, uint32 originalChainId, address originalContract)
        public
        view
        returns (address)
    {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                factory,
                                keccak256(
                                    abi.encode(
                                        originalChainId,
                                        originalContract
                                    )
                                ),
                                TOKEN_INIT_CODE_HASH
                            )
                        )
                    )
                )
            );
    }
}
