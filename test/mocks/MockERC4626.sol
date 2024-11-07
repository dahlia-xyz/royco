// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solady/src/tokens/ERC4626.sol";

contract MockERC4626 is ERC4626 {
    address internal immutable _underlying;
    constructor(
        ERC20 _asset
       
    ) {
        _underlying = address(_asset);
    }

    function asset() public view virtual override returns (address) {
        return _underlying;
    }

    function name() public view virtual override returns (string memory) {
        return "Base Vault";
    }

    function symbol() public view virtual override returns (string memory) {
        return "bVault";
    }

    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 6;
    }

     function _useVirtualShares() internal view virtual override returns (bool) {
        return true;
    }

    function _underlyingDecimals() internal view virtual override returns (uint8) {
        return 18;
    }
}
