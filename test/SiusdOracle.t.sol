// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "./Base.sol";

interface ISiusdOracle {

    function get_price() external view returns (uint256);
    function get_price(
        bool scaled
    ) external view returns (uint256);

}

interface IInfiniFiAccounting {

    function price(
        address asset
    ) external view returns (uint256);

}

contract SiusdOracleTests is Base {

    address public constant IUSD = 0x48f9e38f3070AD8945DFEae3FA70987722E3D89c;
    address public constant SIUSD = 0xDBDC1Ef57537E34680B898E1FEBD3D68c7389bCB;
    address public constant ACCOUNTING = 0x7A5C5dbA4fbD0e1e1A2eCDBe752fAe55f6E842B3;

    ISiusdOracle public siusdOracle;

    function setUp() public override {
        Base.setUp();

        siusdOracle = ISiusdOracle(deployCode("siusd_to_usdc_oracle"));
    }

    function test_siusdOracle() public {
        console2.log("iUSD/USDC price:", IInfiniFiAccounting(ACCOUNTING).price(IUSD));
        console2.log("siUSD/USDC price:", siusdOracle.get_price(false));

        assertEq(siusdOracle.get_price(false), _expectedPrice(), "E0");
        assertEq(siusdOracle.get_price(), _expectedPrice() * 1e6, "E1");
    }

    function test_siusdOracle_capped() public {
        // An accounting price above 1 is capped
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(1.02e18));
        assertEq(siusdOracle.get_price(false), _iusdPerShare(), "E0");
    }

    function test_siusdOracle_noFloor() public {
        // A marked down accounting price flows through, there is no floor
        uint256 _iusdPrice = 0.9e18;
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(_iusdPrice));
        assertEq(siusdOracle.get_price(false), _iusdPerShare() * _iusdPrice / 1e18, "E0");
    }

    function test_siusdOracle_zeroPrice_reverts() public {
        // A zero accounting price reverts instead of pricing the collateral at 0
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(0));
        vm.expectRevert(bytes("wtf"));
        siusdOracle.get_price(false);
    }

    // ============================================================================================
    // Helpers
    // ============================================================================================

    /// @dev iUSD value of one siUSD share
    function _iusdPerShare() internal view returns (uint256) {
        return IERC4626(SIUSD).convertToAssets(1e18);
    }

    /// @dev Mirror the oracle's math against the live accounting
    function _expectedPrice() internal view returns (uint256) {
        uint256 _iusdPrice = IInfiniFiAccounting(ACCOUNTING).price(IUSD);
        if (_iusdPrice > 1e18) _iusdPrice = 1e18;
        return _iusdPerShare() * _iusdPrice / 1e18;
    }

}
