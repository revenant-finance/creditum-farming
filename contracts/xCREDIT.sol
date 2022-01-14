// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Interfaces/IxToken.sol";
import "./ERC20/ERC20.sol";
import "./ERC20/IERC20.sol";
import "./utils/Ownable.sol";
import "./ERC20/ERC20Permit.sol";
import "./ERC20/SafeERC20.sol";

contract xCREDIT is ERC20("xCREDIT", "xCREDIT"), ERC20Permit("xCREDIT"), IxToken, Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable token;

    constructor(IERC20 _token) {
        token = _token;
    }

    function getShareValue() external view override returns (uint256) {
        return totalSupply() > 0
            ? 1e18 * token.balanceOf(address(this)) / totalSupply()
            : 1e18;
    }

    function deposit(uint256 _amount) public override {
        uint256 totalToken = token.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        // if user is first depositer, mint _amount of xTOKEN
        if (totalShares == 0 || totalToken == 0) {
            _mint(msg.sender, _amount);
        } else {
            // loss of precision if totalToken is significantly greater than totalShares
            // seeding the pool with decent amount of TOKEN prevents this
            uint256 myShare = _amount * totalShares / totalToken;
            _mint(msg.sender, myShare);
        }
        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _amount);
    }

    function depositWithPermit(uint256 _amount, Permit calldata permit) external override {
        IERC20Permit(address(token)).permit(
            permit.owner,
            permit.spender,
            permit.amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
        deposit(_amount);
    }

    function withdraw(uint256 _share) external override {
        uint256 totalShares = totalSupply();
        uint256 shareInToken = _share * token.balanceOf(address(this)) / totalShares;
        _burn(msg.sender, _share);
        token.safeTransfer(msg.sender, shareInToken);
        emit Withdraw(msg.sender, _share, shareInToken);
    }

    /// @notice Tokens that are accidentally sent to this contract can be recovered
    function collect(IERC20 _token) external override onlyOwner {
        if (totalSupply() > 0) {
            require(_token != token, "xTOKEN: cannot collect TOKEN");
        }
        uint256 balance = _token.balanceOf(address(this));
        require(balance > 0, "xTOKEN: _token balance is 0");
        _token.safeTransfer(msg.sender, balance);
    }
}