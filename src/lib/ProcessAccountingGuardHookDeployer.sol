// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {ProcessAccountingGuardHook} from "lib/yieldnest-vault-periphery/src/hooks/ProcessAccountingGuardHook.sol";

library ProcessAccountingGuardHookDeployer {
    function deploy(address vault, address timelock, IVaultFactory.ProcessAccountingGuardHookConfig memory config)
        external
        returns (address)
    {
        return address(
            new ProcessAccountingGuardHook(
                vault,
                timelock,
                config.maxTotalAssetsDecreaseRatio,
                config.maxTotalAssetsIncreaseRatio,
                config.maxTotalSupplyIncreaseRatio,
                config.expectedPerformanceFee
            )
        );
    }
}
