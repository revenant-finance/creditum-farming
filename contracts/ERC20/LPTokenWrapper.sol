// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/StorageBuffer.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

// This contract is dedicated to process LP tokens of the users. More precisely, this allows Steak to track how many tokens
// the user has deposited and indicate how much he is eligible to withdraw 
abstract contract LPTokenWrapper is StorageBuffer {
    using SafeERC20 for IERC20;

// Address of STEAK token
    IERC20 public immutable steak;
    // Address of LP token
    IERC20 public immutable lpToken;

// Amount of Lp tokens deposited
    uint256 private _totalSupply;
    // A place where user token balance is stored
    mapping(address => uint256) private _balances;

// Function modifier that calls update reward function
    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    constructor(address _steak, address _lpToken) {
        require(_steak != address(0) && _lpToken != address(0), "NULL_ADDRESS");
        steak = IERC20(_steak);
        lpToken = IERC20(_lpToken);
    }
// View function that provides total supply for the front end 
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
// View function that provides the LP balance of a user
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
// Fuction that is responsible for the receival of LP tokens of the user and the update of the user balance 
    function stake(uint256 amount) virtual public {
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
    }
// Function that is reponsible for releasing LP tokens to the user and for the update of the user balance 
    function withdraw(uint256 amount) virtual public {
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        lpToken.safeTransfer(msg.sender, amount);
    }

//Interface 
    function _updateReward(address account) virtual internal;
}