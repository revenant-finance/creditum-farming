// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20/IERC20.sol";
import "./utils/Ownable.sol";
import "./ERC20/SafeERC20.sol";
import "hardhat/console.sol";

// SteakHouseV2 provides multi-token rewards for the farms of Stake Steak
// This contract is forked from Popsicle.finance which is a fork of SushiSwap's MasterChef Contract
// It intakes one token and allows the user to farm another token. Due to the crosschain nature of Stake Steak we've swapped reward per block
// to reward per second. Moreover, we've implemented safe transfer of reward instead of mint in Masterchef.
// Future is crosschain...

// The contract is ownable untill the DAO will be able to take over.
contract SteakHouseV2 is Ownable {
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256[] RewardDebt; // Reward debt. See explanation below.
        uint256[] RemainingRewards; // Reward Tokens that weren't distributed for user per pool.
        //
        // We do some fancy math here. Basically, any point in time, the amount of STEAK
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.AccRewardsPerShare[i]) - user.RewardDebt[i]
        //
        // Whenever a user deposits or withdraws Staked tokens to a pool. Here's what happens:
        //   1. The pool's `AccRewardsPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 stakingToken; // Contract address of staked token
        uint256 stakingTokenTotalAmount; //Total amount of deposited tokens
        uint32 lastRewardTime; // Last timestamp number that Rewards distribution occurs.
        uint256[] AccRewardsPerShare; // Accumulated reward tokens per share, times 1e12. See below.
        uint256[] AllocPoints; // How many allocation points assigned to this pool. STEAK to distribute per second.
    }

    uint256 public depositFee = 5000; // Withdraw Fee

    uint256 public harvestFee = 100000; //Fee for claiming rewards

    address public harvestFeeReceiver; //harvestFeeReceiver is originally owner of the contract

    address public depositFeeReceiver; //depositFeeReceiver is originally owner of the contract

    IERC20[] public RewardTokens = new IERC20[](5);

    uint256[] public RewardsPerSecond = new uint256[](5);

    uint256[] public totalAllocPoints = new uint256[](5); // Total allocation points. Must be the sum of all allocation points in all pools.

    uint32 public immutable startTime; // The timestamp when Rewards farming starts.

    uint32 public endTime; // Time on which the reward calculation should end

    PoolInfo[] private poolInfo; // Info of each pool.

    mapping(uint256 => mapping(address => UserInfo)) private userInfo; // Info of each user that stakes tokens.

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event FeeCollected(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        IERC20[] memory _RewardTokens,
        uint256[] memory _RewardsPerSecond,
        uint32 _startTime
    ) {
        require(_RewardTokens.length == 5 && _RewardsPerSecond.length == 5);
        RewardTokens = _RewardTokens;

        RewardsPerSecond = _RewardsPerSecond;
        startTime = _startTime;
        endTime = _startTime + 30 days;
        depositFeeReceiver = owner();
        harvestFeeReceiver = owner();
    }

    function changeEndTime(uint32 addSeconds) external onlyOwner {
        endTime += addSeconds;
    }

    // Owner can retreive excess/unclaimed STEAK 7 days after endtime
    // Owner can NOT withdraw any token other than STEAK
    function collect(uint256 _amount) external onlyOwner {
        require(block.timestamp >= endTime + 7 days, "too early to collect");
        for (uint16 i = 0; i <= RewardTokens.length; i++) {
            uint256 balance = RewardTokens[i].balanceOf(address(this));
            require(_amount <= balance, "withdrawing too much");
            RewardTokens[i].safeTransfer(owner(), _amount);
        }
    }

    // Changes Steak token reward per second. Use this function to moderate the `lockup amount`. Essentially this function changes the amount of the reward
    // which is entitled to the user for his token staking by the time the `endTime` is passed.
    //Good practice to update pools without messing up the contract
    function setRewardsPerSecond(
        uint256 _rewardsPerSecond,
        uint16 _rid,
        bool _withUpdate
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        RewardsPerSecond[_rid] = _rewardsPerSecond;
    }

    // How many pools are in the contract
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getPoolInfo(uint256 _pid) public view returns (PoolInfo memory) {
        return poolInfo[_pid];
    }

    function getUserInfo(uint256 _pid, address _user)
        public
        view
        returns (UserInfo memory)
    {
        return userInfo[_pid][_user];
    }

    // Add a new staking token to the pool. Can only be called by the owner.
    // VERY IMPORTANT NOTICE
    // ----------- DO NOT add the same staking token more than once. Rewards will be messed up if you do. -------------
    // Good practice to update pools without messing up the contract
    function add(
        uint256[] calldata _AllocPoints,
        IERC20 _stakingToken,
        bool _withUpdate
    ) external onlyOwner {
        require(_AllocPoints.length == 5);
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime =
            block.timestamp > startTime ? block.timestamp : startTime;
        for (uint256 i = 0; i < totalAllocPoints.length; i++) {
            totalAllocPoints[i] += _AllocPoints[i];
        }
        poolInfo.push(
            PoolInfo({
                stakingToken: _stakingToken,
                stakingTokenTotalAmount: 0,
                lastRewardTime: uint32(lastRewardTime),
                AccRewardsPerShare: new uint256[](5),
                AllocPoints: _AllocPoints
            })
        );
    }

    // Update the given pool's allocation point per reward token. Can only be called by the owner.
    // Good practice to update pools without messing up the contract
    function set(
        uint256 _pid,
        uint256[] calldata _AllocPoints,
        bool _withUpdate
    ) external onlyOwner {
        require(_AllocPoints.length == 5);
        if (_withUpdate) {
            massUpdatePools();
        }
        for (uint16 i = 0; i < totalAllocPoints.length; i++) {
            totalAllocPoints[i] =
                totalAllocPoints[i] -
                poolInfo[_pid].AllocPoints[i] +
                _AllocPoints[i];
            poolInfo[_pid].AllocPoints[i] = _AllocPoints[i];
        }
    }

    function setDepositFee(uint256 _depositFee) external onlyOwner {
        require(_depositFee <= 50000);
        depositFee = _depositFee;
    }

    function setHarvestFee(uint256 _harvestFee) external onlyOwner {
        require(_harvestFee <= 500000);
        harvestFee = _harvestFee;
    }

    function setRewardTokens(IERC20[] calldata _RewardTokens)
        external
        onlyOwner
    {
        require(_RewardTokens.length == 5);
        RewardTokens = _RewardTokens;
    }

    function setHarvestFeeReceiver(address _harvestFeeReceiver)
        external
        onlyOwner
    {
        harvestFeeReceiver = _harvestFeeReceiver;
    }

    function setDepositFeeReceiver(address _depositFeeReceiver)
        external
        onlyOwner
    {
        depositFeeReceiver = _depositFeeReceiver;
    }

    // Return reward multiplier over the given _from to _to time.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        _from = _from > startTime ? _from : startTime;
        if (_from > endTime || _to < startTime) {
            return 0;
        }
        if (_to > endTime) {
            return endTime - _from;
        }
        return _to - _from;
    }

    // View function to see pending rewards on frontend.
    function pendingRewards(uint256 _pid, address _user)
        external
        view
        returns (uint256[] memory)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256[] memory AccRewardsPerShare = pool.AccRewardsPerShare;
        uint256[] memory PendingRewardTokens = new uint256[](5);

        if (
            block.timestamp > pool.lastRewardTime &&
            pool.stakingTokenTotalAmount != 0
        ) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardTime, block.timestamp);
            for (uint256 i = 0; i < RewardTokens.length; i++) {
                if (totalAllocPoints[i] != 0) {
                    uint256 reward =
                        (multiplier *
                            RewardsPerSecond[i] *
                            pool.AllocPoints[i]) / totalAllocPoints[i];
                    AccRewardsPerShare[i] +=
                        (reward * 1e12) /
                        pool.stakingTokenTotalAmount;
                }
            }
        }

        for (uint256 i = 0; i < RewardTokens.length; i++) {
            PendingRewardTokens[i] =
                (user.amount * AccRewardsPerShare[i]) /
                1e12 -
                user.RewardDebt[i] +
                user.RemainingRewards[i];
        }
        return PendingRewardTokens;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        if (pool.stakingTokenTotalAmount == 0) {
            pool.lastRewardTime = uint32(block.timestamp);
            return;
        }
        uint256 multiplier =
            getMultiplier(pool.lastRewardTime, block.timestamp);
        for (uint256 i = 0; i < RewardTokens.length; i++) {
            if (totalAllocPoints[i] != 0) {
                uint256 reward =
                    (multiplier * RewardsPerSecond[i] * pool.AllocPoints[i]) /
                        totalAllocPoints[i];
                pool.AccRewardsPerShare[i] +=
                    (reward * 1e12) /
                    pool.stakingTokenTotalAmount;
                pool.lastRewardTime = uint32(block.timestamp);
            }
        }
    }

    // Deposit staking tokens to SteakHouse for rewards allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.RewardDebt.length == 0 && user.RemainingRewards.length == 0) {
            user.RewardDebt = new uint256[](5);
            user.RemainingRewards = new uint256[](5);
        }
        updatePool(_pid);
        if (user.amount > 0) {
            for (uint256 i = 0; i < RewardTokens.length; i++) {
                uint256 pending =
                    (user.amount * pool.AccRewardsPerShare[i]) /
                        1e12 -
                        user.RewardDebt[i] +
                        user.RemainingRewards[i];
                user.RemainingRewards[i] = safeRewardTransfer(
                    msg.sender,
                    pending,
                    i
                );
            }
        }
        uint256 pendingDepositFee;
        pendingDepositFee = (_amount * depositFee) / 1000000;
        pool.stakingToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        pool.stakingToken.safeTransfer(depositFeeReceiver, pendingDepositFee);
        uint256 amountToStake = _amount - pendingDepositFee;
        user.amount += amountToStake;
        pool.stakingTokenTotalAmount += amountToStake;
        user.RewardDebt = new uint256[](RewardTokens.length);
        for (uint256 i = 0; i < RewardTokens.length; i++) {
            user.RewardDebt[i] =
                (user.amount * pool.AccRewardsPerShare[i]) /
                1e12;
        }
        emit Deposit(msg.sender, _pid, amountToStake);
        emit FeeCollected(msg.sender, _pid, pendingDepositFee);
    }

    // Withdraw staked tokens from SteakHouse.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            user.amount >= _amount,
            "SteakHouse: amount to withdraw is greater than amount available"
        );
        updatePool(_pid);
        for (uint256 i = 0; i < RewardTokens.length; i++) {
            uint256 pending =
                (user.amount * pool.AccRewardsPerShare[i]) /
                    1e12 -
                    user.RewardDebt[i] +
                    user.RemainingRewards[i];
            user.RemainingRewards[i] = safeRewardTransfer(
                msg.sender,
                pending,
                i
            );
        }
        user.amount -= _amount;
        pool.stakingTokenTotalAmount -= _amount;
        for (uint256 i = 0; i < RewardTokens.length; i++) {
            user.RewardDebt[i] =
                (user.amount * pool.AccRewardsPerShare[i]) /
                1e12;
        }
        pool.stakingToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 userAmount = user.amount;
        user.amount = 0;
        user.RewardDebt = new uint256[](0);
        user.RemainingRewards = new uint256[](0);
        pool.stakingToken.safeTransfer(address(msg.sender), userAmount);
        emit EmergencyWithdraw(msg.sender, _pid, userAmount);
    }

    // Safe reward token transfer function. Just in case if the pool does not have enough reward tokens,
    // The function returns the amount which is owed to the user
    function safeRewardTransfer(
        address _to,
        uint256 _amount,
        uint256 _rid
    ) internal returns (uint256) {
        uint256 rewardTokenBalance =
            RewardTokens[_rid].balanceOf(address(this));
        uint256 pendingHarvestFee = (_amount * harvestFee) / 1000000; //! 20% fee for harvesting rewards sent back token holders
        if (rewardTokenBalance == 0) {
            //save some gas fee
            return _amount;
        }
        if (_amount > rewardTokenBalance) {
            //save some gas fee
            pendingHarvestFee = (rewardTokenBalance * harvestFee) / 1000000;
            RewardTokens[_rid].safeTransfer(
                harvestFeeReceiver,
                pendingHarvestFee
            );
            RewardTokens[_rid].safeTransfer(
                _to,
                rewardTokenBalance - pendingHarvestFee
            );
            return _amount - rewardTokenBalance;
        }
        RewardTokens[_rid].safeTransfer(harvestFeeReceiver, pendingHarvestFee);
        RewardTokens[_rid].safeTransfer(_to, _amount - pendingHarvestFee);
        return 0;
    }
}
