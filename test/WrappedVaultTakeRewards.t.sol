// SPDX-Liense-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

// import { MockERC20 } from "test/mocks/MockERC20.sol";

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
uint8 public constant vaultERC20decimals = uint8(18);
uint8 public constant vaultVirtualOffset = uint8(0);
uint8 public constant rewardERC20decimals1 = uint8(6);
uint8 public constant rewardERC20decimals2 = uint8(18);
}

contract RewardMockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}


contract VaultERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, TestLib.vaultERC20decimals) { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract VaultERC4626 is ERC4626 {
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
        return TestLib.vaultVirtualOffset;
    }

    function _useVirtualShares() internal view virtual override returns (bool) {
        return true;
    }

    function _underlyingDecimals() internal view virtual override returns (uint8) {
        return TestLib.vaultERC20decimals;
    }
}

contract WrappedVaultTakeRewardsTest is Test {
    using FixedPointMathLib for *;

    VaultERC20 token = new VaultERC20("WETH", "WETH");
    ERC4626 testVault = ERC4626(address(new VaultERC4626(token)));
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

    RewardMockERC20 rewardToken1;
    RewardMockERC20 rewardToken2;

    function setUp() public {
        testFactory = new WrappedVaultFactory(address(new WrappedVault()), DEFAULT_FEE_RECIPIENT, 0, 0, address(this), address(pointsFactory));
        testIncentivizedVault = testFactory.wrapVault(SolmateERC4626(address(testVault)), address(this), "Incentivized Vault", 0);
        rewardToken1 = new RewardMockERC20("Reward Token USDC", "USDC", TestLib.rewardERC20decimals1);
        rewardToken2 = new RewardMockERC20("Reward Token GHO", "GHO", TestLib.rewardERC20decimals2);

        vm.label(address(testIncentivizedVault), "IncentivizedVault");
        vm.label(address(rewardToken1), "Reward Token USDC");
        vm.label(address(rewardToken2), "Reward Token GHO");
        vm.label(REGULAR_USER, "RegularUser");
        vm.label(REFERRAL_USER, "ReferralUser");
    }

    function testTakeRewards() public {
        // !!!!!! change this params for checking rewards
        uint256 rewardAmount1 = 10_000 * 10 ** TestLib.rewardERC20decimals1; // 10_000 USDC
        uint256 rewardAmount2 = 10_000 * 10 ** TestLib.rewardERC20decimals2; // 10_000 GHO
        uint256 depositAmount = 50 * 10 ** TestLib.vaultERC20decimals; // 50 WETH

        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;
        console.log("Campaign Duration: 30 days");
        console.log("USDC Rewards: ", rewardAmount1 / 10 ** TestLib.rewardERC20decimals1);
        console.log("GHO Rewards: ", rewardAmount2 / 10 ** TestLib.rewardERC20decimals2);
        console.log("User Initial Deposit (WETH): ", depositAmount / 10 ** TestLib.vaultERC20decimals);
        console.log("");

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        testIncentivizedVault.addRewardsToken(address(rewardToken2));

        // Set reward interval for USDC for 30 days
        rewardToken1.mint(address(this), rewardAmount1);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount1);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount1, DEFAULT_FEE_RECIPIENT);

        // Set reward interval for DAHLIA for 30 days
        rewardToken2.mint(address(this), rewardAmount2);
        rewardToken2.approve(address(testIncentivizedVault), rewardAmount2);
        testIncentivizedVault.setRewardsInterval(address(rewardToken2), start, start + duration, rewardAmount2, DEFAULT_FEE_RECIPIENT);

        // Issue #1: Reward rates should be equal for the same amounts of rewards. In this case USDC is `77` and GHO `77160493827160` because of decimals

        // Preview rewards rate for `depositAmount`
        uint256 r1before = testIncentivizedVault.previewRateAfterDeposit(address(rewardToken1), depositAmount);
        uint256 r2before = testIncentivizedVault.previewRateAfterDeposit(address(rewardToken2), depositAmount);
        console.log("USDC reward rate before deposit:", r1before, "decimals", TestLib.rewardERC20decimals1);
        console.log("GHO reward rate before deposit:", r2before, "decimals", TestLib.rewardERC20decimals2);
        console.log("");

        // Deposit `depositAmount` into the vault
        RewardMockERC20(address(token)).mint(REGULAR_USER, depositAmount);
        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        uint256 user1Shares = testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.stopPrank();

        // Issue #2: previewing rate with a small deposit amount returns 0
        // Preview rewards rate for depositing 0.01 more WETH (we expect it to be > 0)
        uint256 r1after = testIncentivizedVault.previewRateAfterDeposit(address(rewardToken1), 1);
        uint256 r2after = testIncentivizedVault.previewRateAfterDeposit(address(rewardToken2), 1);
        console.log("USDC reward rate after deposit: ", r1after);
        console.log("GHO reward rate after deposit: ", r2after);
//        assertGt(r1after,0, "USDC reward rate after deposit > 0");
//        assertGt(r2after,0, "GHO reward rate after deposit > 0");

        {
            (,, uint96 rate) = testIncentivizedVault.rewardToInterval(address(rewardToken1));
            console.log("USDC rewardToInterval.rate: ", rate);
            assertGt(rate, 0, "reward1 rewardToInterval.rate > 0");
        }
        {
            (,, uint96 rate) = testIncentivizedVault.rewardToInterval(address(rewardToken2));
            console.log("GHO rewardToInterval.rate:        ", rate);
            assertGt(rate, 0, "reward2 rewardToInterval.rate > 0");
        }

    }
}
