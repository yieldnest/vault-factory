// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title FlexProvider
/// @notice Rate provider for a Main Vault backed by a flex strategy: the effective base asset and
/// the default asset are priced at a fixed par rate, and strategy shares at the strategy's live
/// redemption rate.
/// @dev Generalized from yieldnest-vault/src/module/Provider.sol, without the hardcoded mainnet
/// asset addresses.
contract FlexProvider {
    address public immutable baseAsset;
    address public immutable defaultAsset;
    address public immutable strategy;
    uint256 public immutable parRate;

    error UnsupportedAsset(address asset);
    error ZeroAddress();
    error InvalidStrategy(address strategy, address strategyAsset, uint8 strategyDecimals);

    constructor(address _baseAsset, address _defaultAsset, address _strategy, uint256 _parRate) {
        if (_baseAsset == address(0) || _defaultAsset == address(0) || _strategy == address(0)) revert ZeroAddress();

        // getRate assumes convertToAssets(parRate) yields a par-rate-denominated strategy rate,
        // which only holds when the strategy's shares are denominated in the default asset with
        // matching decimals.
        address strategyAsset = IERC4626(_strategy).asset();
        uint8 strategyDecimals = IERC20Metadata(_strategy).decimals();
        if (strategyAsset != _defaultAsset || strategyDecimals != IERC20Metadata(_defaultAsset).decimals()) {
            revert InvalidStrategy(_strategy, strategyAsset, strategyDecimals);
        }

        baseAsset = _baseAsset;
        defaultAsset = _defaultAsset;
        strategy = _strategy;
        parRate = _parRate;
    }

    function getRate(address asset) public view returns (uint256) {
        if (asset == baseAsset || asset == defaultAsset) {
            return parRate;
        }

        if (asset == strategy) {
            return IERC4626(strategy).convertToAssets(parRate);
        }

        revert UnsupportedAsset(asset);
    }
}
