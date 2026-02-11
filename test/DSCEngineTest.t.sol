// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public COLLATERAL_AMOUNT = 10 ether;
    uint256 public STARTING_ERC20_BALANCE = 10 ether;
    uint256 public MINT_DSC_AMOUNT = 4 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////////////////////////////
    ///// Constructor Tests /////////////
    /////////////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqual.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////////////////
    ///// Price Tests /////////////
    ///////////////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30000e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // 2000$/ETH, 100$ = ? -> 100/2000 -> 0.05
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////
    /// mintDsc Tests ///
    /////////////////////

    function testRevertIfAmountDscToMintIsZero() public {
        uint256 amountDscToMint = 0;
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(amountDscToMint);
    }

    // Helper function
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        view
        returns (uint256)
    {
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        uint256 collateralAdjustedForThreshold =
            (collateralValueInUsd * engine.getLiquidationThreshold()) / engine.getLiquidationPrecision();

        return (collateralAdjustedForThreshold * engine.getPrecision()) / totalDscMinted;
    }

    function testMintDscRevertIfHealthFactorBreaks() public depositedCollateral {
        uint256 collateralValueInUsd = engine.getUsdValue(weth, COLLATERAL_AMOUNT);

        uint256 maxMintableDsc =
            (collateralValueInUsd * engine.getLiquidationThreshold()) / engine.getLiquidationPrecision();

        uint256 amountDscToMint = maxMintableDsc + 1;

        uint256 expectedHealthFactor = _calculateHealthFactor(maxMintableDsc + 1, collateralValueInUsd);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(amountDscToMint);
    }

    function testMintDscSuccess() public depositedCollateral {
        uint256 collateralValueInUsd = engine.getUsdValue(weth, COLLATERAL_AMOUNT);

        uint256 maxMintableDsc =
            (collateralValueInUsd * engine.getLiquidationThreshold()) / engine.getLiquidationPrecision();

        uint256 mintAmount = maxMintableDsc / 2; // comfortably safe

        vm.prank(USER);
        engine.mintDsc(mintAmount);

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount);

        assertEq(dsc.balanceOf(USER), mintAmount);

        uint256 hf = engine.getHealthFactor(USER);

        assertGe(hf, engine.getMinHealthFactor());
    }

    function testMintDscAtExactHealthFactorOneWorks() public depositedCollateral {
        uint256 collateralValueInUsd = engine.getUsdValue(weth, COLLATERAL_AMOUNT);

        uint256 maxMintableDsc =
            (collateralValueInUsd * engine.getLiquidationThreshold()) / engine.getLiquidationPrecision();

        vm.prank(USER);
        engine.mintDsc(maxMintableDsc);

        uint256 hf = engine.getHealthFactor(USER);
        assertEq(hf, engine.getMinHealthFactor());
    }

    /////////////////////
    /// burnDsc Tests ///
    /////////////////////

    function testBurnDscRevertIfAmountDscToBurnIsZero() public {
        uint256 amountDscToBurn = 0;
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(amountDscToBurn);
    }

    modifier mintedDsc() {
        vm.prank(USER);
        engine.mintDsc(MINT_DSC_AMOUNT);
        _;
    }

    function testBurnDscRevertIfAmountDscToBurnIsMoreThanUserBalance() public depositedCollateral mintedDsc {
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        uint256 burnAmount = totalDscMinted + 1;
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__BurnAmountExceedsBalance.selector);
        engine.burnDsc(burnAmount);
    }

    function testBurnDscSuccess() public depositedCollateral mintedDsc {
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        uint256 burnAmount = totalDscMinted / 2;
        uint256 hfBefore = engine.getHealthFactor(USER);

        vm.startPrank(USER);
        dsc.approve(address(engine), burnAmount);
        engine.burnDsc(burnAmount);
        vm.stopPrank();

        (uint256 mintedAfter,) = engine.getAccountInformation(USER);
        assertEq(mintedAfter, totalDscMinted - burnAmount);
        assertEq(dsc.balanceOf(USER), totalDscMinted - burnAmount);
        uint256 hfAfter = engine.getHealthFactor(USER);
        assertGt(hfAfter, hfBefore);
    }

    function testBurnAllDscSetsHealthFactorToMax() public depositedCollateral mintedDsc {
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);

        vm.startPrank(USER);
        dsc.approve(address(engine), totalDscMinted);
        engine.burnDsc(totalDscMinted);
        vm.stopPrank();

        (uint256 mintedAfter,) = engine.getAccountInformation(USER);
        assertEq(mintedAfter, 0);

        uint256 hf = engine.getHealthFactor(USER);
        assertEq(hf, type(uint256).max);
    }

    ///////////////////////////////
    /// redeemCollateral Tests ////
    ///////////////////////////////

    function testRedeemCollateralRevertIfCollateralAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralRevertIfRedeemAmountExceedsCollateral() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__RedeemAmountExceedsCollateral.selector);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT + 1);
    }

    function testRedeemCollateralRevertIfHealthFactorBreaks() public depositedCollateral mintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 minRequiredCollateralUsd =
            (totalDscMinted * engine.getLiquidationPrecision()) / engine.getLiquidationThreshold();
        uint256 maxRedeemableCollateralInUsd = collateralValueInUsd - minRequiredCollateralUsd;
        uint256 redeemAmount = engine.getTokenAmountFromUsd(weth, maxRedeemableCollateralInUsd);
        uint256 remainingCollateralUsd = collateralValueInUsd - engine.getUsdValue(weth, redeemAmount + 1);
        uint256 hfAfterRedeem = _calculateHealthFactor(totalDscMinted, remainingCollateralUsd);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, hfAfterRedeem));
        engine.redeemCollateral(weth, redeemAmount + 1);
    }

    ///////////////////////////////
    /// depositCollateral Tests ///
    ///////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // Ensures DSCEngine rejects collateral tokens without a price feed,
    // even if the user has balance and approval
    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        ERC20Mock(randomToken).mint(USER, STARTING_ERC20_BALANCE);
        assertEq(engine.getCollateralTokenPriceFeed(address(randomToken)), address(0));

        ERC20Mock(address(randomToken)).approve(address(engine), COLLATERAL_AMOUNT);

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), COLLATERAL_AMOUNT);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    // After depositing collateral:
    // - No DSC should be minted
    // - Account information should reflect the USD value of deposited collateral
    // This validates both collateral accounting and USD valuation logic.
    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = engine.getUsdValue(weth, COLLATERAL_AMOUNT);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }
}
