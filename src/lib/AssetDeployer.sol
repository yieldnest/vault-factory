// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IWrappedToken} from "src/interfaces/external/IWrappedToken.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {UninitializedTransparentUpgradeableProxy} from "src/proxy/UninitializedTransparentUpgradeableProxy.sol";

library AssetDeployer {
    uint8 internal constant VAULT_DECIMALS = 18;

    struct Assets {
        address effectiveBaseAsset;
        address defaultAsset;
        uint256 defaultAssetIndex;
        address wrappedToken;
    }

    function prepare(IRegistry registry, address baseAsset, address timelock) external returns (Assets memory assets) {
        uint8 baseAssetDecimals = IERC20Metadata(baseAsset).decimals();
        assets.defaultAsset = baseAsset;

        if (baseAssetDecimals == VAULT_DECIMALS) {
            assets.effectiveBaseAsset = baseAsset;
        } else {
            assets.wrappedToken = _deployWrappedToken(registry, baseAsset, baseAssetDecimals, timelock);
            assets.effectiveBaseAsset = assets.wrappedToken;
        }

        assets.defaultAssetIndex = assets.effectiveBaseAsset == assets.defaultAsset ? 0 : 1;
    }

    function _deployWrappedToken(IRegistry registry, address underlying, uint8 underlyingDecimals, address timelock)
        private
        returns (address wrappedToken)
    {
        wrappedToken = address(
            new UninitializedTransparentUpgradeableProxy(registry.valueOf(RegistryKeys.WRAPPED_TOKEN), timelock)
        );
        IWrappedToken(wrappedToken)
            .initialize(
                IERC20(underlying),
                _wrappedTokenName(underlying),
                _wrappedTokenSymbol(underlying),
                VAULT_DECIMALS,
                VAULT_DECIMALS - underlyingDecimals
            );
    }

    function _wrappedTokenName(address underlying) private view returns (string memory) {
        return string.concat("Wrapped ", IERC20Metadata(underlying).name());
    }

    function _wrappedTokenSymbol(address underlying) private view returns (string memory) {
        return string.concat("W", IERC20Metadata(underlying).symbol());
    }
}
