// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

import {ICatFactory} from "./interfaces/ICatFactory.sol";
import {IDaddy} from "./interfaces/IDaddy.sol";
import {IMorphoOracleFactory} from "./interfaces/IMorphoOracleFactory.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";

import "forge-std/Script.sol";

// ---- Usage ----

// forge script script/DeployMarket.s.sol:DeployMarket --verify --slow -g 250 --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

contract DeployMarket is Script {

    // Parameters
    address public constant BORROW_TOKEN = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
    address public constant COLLATERAL_TOKEN = address(0xAc37729B76db6438CE62042AE1270ee574CA7571); // yvWETH-2

    // Deployed contracts
    ICatFactory public constant FACTORY = ICatFactory(0xfFc787AD990dA8f73dDA2B971Dce31C0D9d2501F);
    IDaddy public constant DADDY = IDaddy(0x4e8341C77c94cCE982AB96d92BB28D69f4638290);
    IRegistry public constant REGISTRY = IRegistry(0x9117440a7D03238905d1C8908157Bd7a547c77c8);
    IMorphoOracleFactory public constant MORPHO_ORACLE_FACTORY = IMorphoOracleFactory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);

    function run() public {
        uint256 _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_pk);
        require(_deployer == address(0x000005281a2b04A182085D37cC9E6dD552795caa), "!johnny.flexmeow.eth");
        console.log("Deployer address: %s", _deployer);

        vm.startBroadcast(_pk);

        // Deploy a Morpho oracle for yvWETH-2/WETH (vault conversion only) and wrap it in the Flex adapter
        address _morphoOracle = MORPHO_ORACLE_FACTORY.createMorphoChainlinkOracleV2(
            COLLATERAL_TOKEN, // baseVault: yvWETH-2
            1e18, // baseVaultConversionSample
            address(0), // baseFeed1
            address(0), // baseFeed2
            18, // baseTokenDecimals: WETH
            address(0), // quoteVault
            1, // quoteVaultConversionSample
            address(0), // quoteFeed1
            address(0), // quoteFeed2
            18, // quoteTokenDecimals: WETH
            bytes32(0) // salt
        );
        address _priceOracle = deployCode("morpho_oracle", abi.encode(_morphoOracle, BORROW_TOKEN, COLLATERAL_TOKEN));

        // Deploy market
        (address _troveManager, address _sortedTroves, address _dutchDesk, address _auction, address _lender) = FACTORY.deploy(
            ICatFactory.DeployParams({
                borrow_token: BORROW_TOKEN,
                collateral_token: COLLATERAL_TOKEN,
                price_oracle: _priceOracle,
                minimum_debt: 0.1 ether, // 0.1 WETH
                safe_collateral_ratio: 120, // 120%
                minimum_collateral_ratio: 110, // 110%
                max_penalty_collateral_ratio: 105, // 105%
                min_liquidation_fee: 50, // 0.5%
                max_liquidation_fee: 500, // 5%
                upfront_interest_period: 1 days,
                interest_rate_adj_cooldown: 7 days,
                repay_cooldown: 10 minutes,
                minimum_price_buffer_percentage: 1e18 - 1e16, // 99%
                starting_price_buffer_percentage: 1e18, // 100%
                re_kick_starting_price_buffer_percentage: 1e18 + 1e15, // 100.1%
                step_duration: 60, // 1 minute
                step_decay_rate: 1, // 0.01%
                auction_length: 1 days,
                salt: bytes32(uint256(420))
            })
        );

        // // Accept Lender management
        // DADDY.execute(address(_lender), abi.encodeWithSelector(ITokenizedStrategy.acceptManagement.selector), 0, true);

        // // Endorse market
        // DADDY.execute(address(REGISTRY), abi.encodeWithSelector(IRegistry.endorse.selector, _troveManager), 0, true);

        console2.log("---------------------------------");
        console2.log("Morpho Oracle: ", _morphoOracle);
        console2.log("Price Oracle: ", _priceOracle);
        console2.log("Trove Manager: ", _troveManager);
        console2.log("Sorted Troves: ", _sortedTroves);
        console2.log("Dutch Desk: ", _dutchDesk);
        console2.log("Auction: ", _auction);
        console2.log("Lender: ", _lender);
        console2.log("---------------------------------");

        vm.stopBroadcast();
    }

}
