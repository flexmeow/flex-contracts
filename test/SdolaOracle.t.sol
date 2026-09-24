// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "./Base.sol";

interface ISdolaOracle {

    function get_price() external view returns (uint256);
    function get_price(
        bool scaled
    ) external view returns (uint256);

}

interface ICurveStableSwapNG {

    function price_oracle(
        uint256 i
    ) external view returns (uint256);

}

contract SdolaOracleTests is Base {

    address public constant SDOLA = 0xb45ad160634c528Cc3D2926d9807104FA3157305;
    address public constant CURVE_POOL = 0x8b83c4aA949254895507D09365229BC3a8c7f710;

    ISdolaOracle public sdolaOracle;

    function setUp() public override {
        Base.setUp();

        sdolaOracle = ISdolaOracle(deployCode("sdola_to_usdc_oracle"));
    }

    function test_sdolaOracle() public {
        uint256 _usdsPrice = ICurveStableSwapNG(CURVE_POOL).price_oracle(0);
        console2.log("USDS/DOLA price:", _usdsPrice);
        console2.log("sDOLA/USDC price:", sdolaOracle.get_price(false));

        assertEq(sdolaOracle.get_price(false), _expectedPrice(), "E0");
        assertEq(sdolaOracle.get_price(), _expectedPrice() * 1e6, "E1");
    }

    function test_sdolaOracle_capped() public {
        // An EMA implying DOLA above 1.01 USDC is capped
        vm.mockCall(CURVE_POOL, abi.encodeWithSignature("price_oracle(uint256)", 0), abi.encode(0.98e18));
        assertEq(sdolaOracle.get_price(false), _dolaPerShare() * 1.01e18 / 1e18, "E0");
    }

    function test_sdolaOracle_noFloor() public {
        // A depegged EMA flows through, there is no floor
        uint256 _ema = 1.1e18;
        vm.mockCall(CURVE_POOL, abi.encodeWithSignature("price_oracle(uint256)", 0), abi.encode(_ema));
        assertEq(sdolaOracle.get_price(false), _dolaPerShare() * (1e36 / _ema) / 1e18, "E0");
    }

    // ============================================================================================
    // Helpers
    // ============================================================================================

    /// @dev DOLA value of one sDOLA share
    function _dolaPerShare() internal view returns (uint256) {
        return IERC4626(SDOLA).convertToAssets(1e18);
    }

    /// @dev Mirror the oracle's math against the live pool state
    function _expectedPrice() internal view returns (uint256) {
        uint256 _dolaPrice = 1e36 / ICurveStableSwapNG(CURVE_POOL).price_oracle(0);
        if (_dolaPrice > 1.01e18) _dolaPrice = 1.01e18;
        return _dolaPerShare() * _dolaPrice / 1e18;
    }

}
