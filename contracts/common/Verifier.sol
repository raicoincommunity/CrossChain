// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./CustomEIP712Upgradeable.sol";
import "./IValidatorManager.sol";
import "./errors.sol";

abstract contract Verifier is Initializable, CustomEIP712Upgradeable {
    uint256 private constant _REWARD_FACTOR = 1e9;

    IValidatorManager private _validatorManager;
    uint256 private _fee;
    uint256 private _totalFee;

    event FeeCharged(address indexed sender, uint256 fee);
    event RewardSent(address indexed recipient, uint256 amount);

    modifier onlyValidatorManager() {
        if (msg.sender != address(_validatorManager)) revert NotCalledByValidatorManager();
        _;
    }

    modifier chargeFee(uint256 fee) {
        if (fee < _fee) revert FeeTooLow();
        if (fee > 0) {
            _totalFee += fee;
            emit FeeCharged(msg.sender, fee);
        }
        _;
    }

    function __Verifier_init(IValidatorManager validatorManager) internal onlyInitializing {
        __Verifier_init_unchained(validatorManager);
    }

    function __Verifier_init_unchained(IValidatorManager validatorManager)
        internal
        onlyInitializing
    {
        _validatorManager = validatorManager;
    }

    function setFee(uint256 fee) external onlyValidatorManager {
        _fee = fee;
    }

    function sendReward(address recipient, uint256 share) external onlyValidatorManager {
        uint256 total = _totalFee;
        uint256 amount = 0;
        if (share >= _REWARD_FACTOR) {
            amount = total;
        } else {
            amount = (total * share) / _REWARD_FACTOR;
        }

        if (amount == 0) {
            return;
        }
        _totalFee = total - amount;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert SendRewardFailed();

        emit RewardSent(recipient, amount);
    }

    function getFee() public view returns (uint256) {
        return _fee;
    }

    function verify(bytes32 structHash, bytes calldata signatures) public view returns (bool) {
        bytes32 typedHash = _hashTypedDataV4(structHash);
        return _validatorManager.verifyTypedData(typedHash, signatures);
    }
}