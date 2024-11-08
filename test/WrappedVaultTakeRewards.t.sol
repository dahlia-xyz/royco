// SPDX-Liense-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 as SolmateERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ERC4626 } from "lib/solady/src/tokens/ERC4626.sol";

import { WrappedVault } from "src/WrappedVault.sol";
import { WrappedVaultFactory } from "src/WrappedVaultFactory.sol";

import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";

import { PointsFactory } from "src/PointsFactory.sol";

import { Test, console } from "forge-std/Test.sol";

library TestLib {
uint8 public constant _decimals = uint8(6);
}

contract HackedERC20 is ERC20 {

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, TestLib._decimals) { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public {
        _burn(to, amount);
    }
}

contract HackERC4626 is ERC4626 {
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
        return 0;
    }

    function _useVirtualShares() internal view virtual override returns (bool) {
        return true;
    }

    function _underlyingDecimals() internal view virtual override returns (uint8) {
        return TestLib._decimals;
    }
}

contract WrappedVaultTakeRewardsTest is Test {
    using FixedPointMathLib for *;

    HackedERC20 token = new HackedERC20("Mock Token", "MOCK");
    ERC4626 testVault = ERC4626(address(new HackERC4626(token)));
    WrappedVault testIncentivizedVault;

    PointsFactory pointsFactory = new PointsFactory(POINTS_FACTORY_OWNER);
    WrappedVaultFactory testFactory;
    uint256 constant WAD = 1e18;

    uint256 constant DEFAULT_REFERRAL_FEE = 0.025e18;
    uint256 constant DEFAULT_FRONTEND_FEE = 0.025e18;
    uint256 constant DEFAULT_PROTOCOL_FEE = 0.05e18;

    address constant DEFAULT_FEE_RECIPIENT = address(0x33f120);

    address public constant POINTS_FACTORY_OWNER = address(0x1);
    address public constant REGULAR_USER = address(0x33f121);
    address public constant REGULAR_USER2 = address(0x33f122);
    address public constant REFERRAL_USER = address(0x33f123);

    MockERC20 rewardToken1;
    MockERC20 rewardToken2;

    function setUp() public {
        testFactory = new WrappedVaultFactory(DEFAULT_FEE_RECIPIENT, 0, 0, address(this), address(pointsFactory));
        testIncentivizedVault = testFactory.wrapVault(SolmateERC4626(address(testVault)), address(this), "Incentivized Vault", 0);

        rewardToken1 = new MockERC20("Reward Token 1", "RWD1");
        rewardToken2 = new MockERC20("Reward Token 2", "RWD2");

        vm.label(address(testIncentivizedVault), "IncentivizedVault");
        vm.label(address(rewardToken1), "RewardToken1");
        vm.label(address(rewardToken2), "RewardToken2");
        vm.label(REGULAR_USER, "RegularUser");
        vm.label(REFERRAL_USER, "ReferralUser");
    }

    function testTakeRewards() public {
        uint256 rewardAmount = 100000 * 10 ** TestLib._decimals;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;
        console.log("duration", duration);

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, DEFAULT_FEE_RECIPIENT);
        assertEq(rewardToken1.balanceOf(address(testIncentivizedVault)), rewardAmount, "reward token on vault");
        uint256 depositAmount = 1000e6; // 1000 USDC
        console.log("v", rewardToken1.balanceOf(address(testIncentivizedVault)));
        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);
        MockERC20(address(token)).mint(REGULAR_USER2, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.stopPrank();

        vm.startPrank(REGULAR_USER2);
        token.approve(address(testIncentivizedVault), depositAmount);
        testIncentivizedVault.deposit(depositAmount, REGULAR_USER2);
        vm.stopPrank();

        console.log("v1", rewardToken1.balanceOf(address(testIncentivizedVault)));
        console.log("u1", rewardToken1.balanceOf(REGULAR_USER));
        console.log("u2", rewardToken1.balanceOf(REGULAR_USER2));
        console.log("f1", rewardToken1.balanceOf(DEFAULT_FEE_RECIPIENT));

        // 1000 USDC deposited by single user.
        vm.warp(start + duration / 2);
        vm.startPrank(REGULAR_USER);
        testIncentivizedVault.claim(REGULAR_USER);
        vm.stopPrank();
        vm.startPrank(REGULAR_USER2);
        testIncentivizedVault.claim(REGULAR_USER2);
        vm.stopPrank();
//        assertEq(rewardToken1.balanceOf(address(testIncentivizedVault)), rewardAmount, "reward token on vault after claim");
//        assertEq(testIncentivizedVault.currentUserRewards(address(rewardToken1), REFERRAL_USER), rewardAmount * 100 / duration);
        vm.startPrank(REGULAR_USER);
        testIncentivizedVault.withdraw(depositAmount, REGULAR_USER, REGULAR_USER);
        testIncentivizedVault.claim(REGULAR_USER);

        console.log("v1", rewardToken1.balanceOf(address(testIncentivizedVault)));
        console.log("u1", rewardToken1.balanceOf(REGULAR_USER));
        console.log("u2", rewardToken1.balanceOf(REGULAR_USER2));
        console.log("f1", rewardToken1.balanceOf(DEFAULT_FEE_RECIPIENT));

        vm.warp(start + duration + 1);
        vm.startPrank(REGULAR_USER2);
        testIncentivizedVault.claim(REGULAR_USER2);
        vm.stopPrank();
        console.log("v1", rewardToken1.balanceOf(address(testIncentivizedVault)));
        console.log("u1", rewardToken1.balanceOf(REGULAR_USER));
        console.log("u2", rewardToken1.balanceOf(REGULAR_USER2));
        console.log("f1", rewardToken1.balanceOf(DEFAULT_FEE_RECIPIENT));
        vm.stopPrank();
//        assertEq(testIncentivizedVault.currentUserRewards(address(rewardToken1), REFERRAL_USER), rewardAmount * 100 / duration);
    }
}
