// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {FeeHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";

library FeeHookDeployer {
    function deploy(address vault, address timelock, uint256 performanceFee, address feeRecipient)
        external
        returns (address)
    {
        return address(new FeeHooks(vault, timelock, performanceFee, feeRecipient, _config()));
    }

    function _config() private pure returns (IHooks.Config memory) {
        return IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });
    }
}
