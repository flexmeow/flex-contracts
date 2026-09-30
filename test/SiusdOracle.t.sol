// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "./Base.sol";

interface ISiusdOracle {

    function approved_iusd_price() external view returns (uint256);
    function approve_iusd_price(
        uint256 iusd_price
    ) external;
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

        assertEq(siusdOracle.approved_iusd_price(), 1e18, "E0");
        assertEq(siusdOracle.get_price(false), _expectedPrice(), "E1");
        assertEq(siusdOracle.get_price(), _expectedPrice() * 1e6, "E2");
    }

    function test_siusdOracle_unapprovedMarkdown() public {
        // A markdown in the accounting is ignored until Daddy approves it
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(0.9e18));
        assertEq(siusdOracle.get_price(false), _iusdPerShare(), "E0");
    }

    function test_siusdOracle_approvedMarkdown() public {
        // Once Daddy approves the accounting's price, it flows through
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(0.9e18));
        vm.prank(address(DADDY));
        siusdOracle.approve_iusd_price(0.9e18);
        assertEq(siusdOracle.get_price(false), _iusdPerShare() * 0.9e18 / 1e18, "E0");

        // Another change in the accounting is ignored again until Daddy approves it
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(0.8e18));
        assertEq(siusdOracle.get_price(false), _iusdPerShare(), "E1");
    }

    function test_siusdOracle_aboveOne() public {
        // An accounting price above 1 is never used, since Daddy cannot approve it
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(1.02e18));
        assertEq(siusdOracle.get_price(false), _iusdPerShare(), "E0");
    }

    function test_siusdOracle_zeroPrice_reverts() public {
        // An approved zero price reverts instead of pricing the collateral at 0
        vm.mockCall(ACCOUNTING, abi.encodeWithSelector(IInfiniFiAccounting.price.selector, IUSD), abi.encode(0));
        vm.prank(address(DADDY));
        siusdOracle.approve_iusd_price(0);
        vm.expectRevert(bytes("wtf"));
        siusdOracle.get_price(false);
    }

    function test_approveIusdPrice(
        uint256 _iusdPrice
    ) public {
        _iusdPrice = bound(_iusdPrice, 0, 1e18);

        vm.prank(address(DADDY));
        siusdOracle.approve_iusd_price(_iusdPrice);
        assertEq(siusdOracle.approved_iusd_price(), _iusdPrice, "E0");
    }

    function test_approveIusdPrice_aboveOne_reverts(
        uint256 _iusdPrice
    ) public {
        _iusdPrice = bound(_iusdPrice, 1e18 + 1, type(uint256).max);

        vm.prank(address(DADDY));
        vm.expectRevert("!iusd_price");
        siusdOracle.approve_iusd_price(_iusdPrice);
    }

    function test_approveIusdPrice_notDaddy_reverts(
        address _caller,
        uint256 _iusdPrice
    ) public {
        vm.assume(_caller != address(DADDY));

        vm.prank(_caller);
        vm.expectRevert("bad daddy");
        siusdOracle.approve_iusd_price(_iusdPrice);
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
        if (_iusdPrice != siusdOracle.approved_iusd_price()) _iusdPrice = 1e18;
        return _iusdPerShare() * _iusdPrice / 1e18;
    }

}
