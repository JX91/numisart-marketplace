// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
*
* MIT License
* ===========
*
* Copyright (c) 2022 
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE

 */

interface IAlpacaLending {
    
    // View function to see balance of this contract on frontend.
    function balanceOf(address _user)
        external
        view
        returns (uint256);

    // Deposit tokens to MasterChef.
    function deposit( uint256 _amount) external payable;

    // Withdraw  tokens from MasterChef.
    function withdraw( uint256 _amount) external;

    // Return the total token entitled to the token holders.
    function totalToken() external view returns (uint256);

    //Returns the amount of tokens in existence.
    function totalSupply() external view returns (uint256);

}

//market place interface
interface IMarketPlace{
    struct nftProfitSharing{
        address pioneer;
        address[10] exOwner;
        uint256 ownerCount;
    }
    function nftProfitDetail(uint256 _tokenId,address _nftContract ) external view returns (nftProfitSharing memory);

}

contract BNBStrategy is ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct userInfo{
        uint256 want;
        uint256 wantFreeze;
        uint256 share;
    }
    address immutable public wantAddress;
    address immutable pmgAddress;
    address immutable devAddress;
    address immutable nftContractOwner;
    address immutable public govAddress; 
    uint256 public shareLockedTotal ;
    address immutable public farmContractAddress;
    address public marketContractAddress;
    mapping(address=>userInfo) public userInfos;
    constructor(address _pmgAddress, address _devAddress,address _nftContractOwner,address _tokenAddress,address _farmContract, address _marketContract){
        pmgAddress = _pmgAddress;
        devAddress = _devAddress;
        nftContractOwner = _nftContractOwner;
        govAddress = msg.sender;
        wantAddress = _tokenAddress;
        farmContractAddress = _farmContract;
        marketContractAddress = _marketContract;
    }

    /* deposit
        condition
            * only market place can call
        i)action equal 0 = deposit to alpaca,fresh fund coming in
        ii)action equal 1 = no deposit to alpaca,only pool balance update
        iii)isFreeze equal 0 = no freeze want will involve, isFreeze equal 1 = user freeze want will involve
     */
    function deposit(uint256 _wantAmt,address seller,uint256 _tokenId,address buyer,uint256 action,uint256 isFreeze,address _nftContract) external payable nonReentrant {
        require(msg.sender == marketContractAddress,"only market allow" );
        uint256 sharesTotal;
        if(action == 0){
            /* deposit to alpaca */
            IAlpacaLending(farmContractAddress).deposit{value:msg.value}(msg.value);
            /* calculate how much ibnb as share will get from deposit */
            sharesTotal = (msg.value).mul(IAlpacaLending(farmContractAddress).totalSupply()).div(IAlpacaLending(farmContractAddress).totalToken());
            /* update share total in this address */
            shareLockedTotal = shareLockedTotal.add(sharesTotal);  

        }else if (action == 1){
            /* get buyer pool detail */
            userInfo memory user = userInfos[buyer];
            /* calculate involve share in this transaction */
            sharesTotal = _wantAmt *  (user.share).div(user.want);
            /* deduct the share amount */
            if(isFreeze != 0){
                require(userInfos[buyer].want - userInfos[buyer].wantFreeze >= _wantAmt,"insufficient fund");
                userInfos[buyer].wantFreeze -= _wantAmt;
            }
            userInfos[buyer].want -= _wantAmt;
            userInfos[buyer].share -= sharesTotal;
        }
        /* get exOwner detail and update distribute amount to pool */
        IMarketPlace.nftProfitSharing memory nftDetail = IMarketPlace(marketContractAddress).nftProfitDetail(_tokenId,_nftContract);
        uint256 exOwnerProfitWant;
        uint256 exOwnerProfitShares;
        _addBalance(seller,_wantAmt * 840 / 1000,sharesTotal * 840 / 1000);
        _addBalance(devAddress,_wantAmt * 50 / 1000,sharesTotal * 50 / 1000);
        _addBalance(pmgAddress,_wantAmt * 25 / 1000,sharesTotal * 25 / 1000);
        _addBalance(nftContractOwner,_wantAmt * 10 / 1000,sharesTotal * 10 / 1000);
        _addBalance(nftDetail.pioneer,_wantAmt * 50 / 1000,sharesTotal * 50 / 1000);
        if(nftDetail.ownerCount > 0){
            exOwnerProfitWant = _wantAmt * 25 / 1000 / nftDetail.ownerCount;
            exOwnerProfitShares = sharesTotal * 25 / 1000 / nftDetail.ownerCount;
            for(uint256 i ; i<nftDetail.ownerCount; i++){
                _addBalance(nftDetail.exOwner[i],exOwnerProfitWant,exOwnerProfitShares);
            }
        }else{
            _addBalance(devAddress,_wantAmt * 25 / 1000,sharesTotal * 25 / 1000);
        }
        
        
    } 

    /* direct deposit to strategy
        condition
            * only market place can call if involve freeze balance
        i)isFreeze equal 0 = no freeze want will involve, isFreeze equal 1 = user freeze want will involve
     */
    function directDeposit(uint256 _wantAmt,address _user,uint256 isFreeze) external payable nonReentrant {
        IAlpacaLending(farmContractAddress).deposit{value:msg.value}(msg.value);
        /* get this address total token */
        uint256 total  = (IAlpacaLending(farmContractAddress).totalToken());
        /* get the amount include interest */
        uint256 sharesTotal = (msg.value).mul(IAlpacaLending(farmContractAddress).totalSupply()).div(total);
        /* update pool balance for user */
        if(isFreeze == 1){
            require(msg.sender == marketContractAddress,"only market allow" );
            userInfos[_user].wantFreeze += msg.value ;
        }
        userInfos[_user].want += msg.value ;
        userInfos[_user].share += sharesTotal ;
        shareLockedTotal = shareLockedTotal.add(sharesTotal);  
    } 

    /* lock fund for user
        condition
            * only market place can call 
            * user available balance must greater than request lock amount
     */
    function lockFund(uint256 _wantAmt,address _user) external  {
        require(msg.sender == marketContractAddress,"only market allow" );
        require(userInfos[_user].want - userInfos[_user].wantFreeze >= _wantAmt,"insufficient fund");
        /* freeze user amount */
        userInfos[_user].wantFreeze += _wantAmt ;
    } 

    /* unlock fund for user
        condition
            * only market place can call 
            * user freeze balance must greater than request unlock amount
     */
    function unlockFund(uint256 _wantAmt,address _user) external  {
        require(msg.sender == marketContractAddress,"only market allow" );
        require(userInfos[_user].wantFreeze>= _wantAmt,"insufficient frozen fund");
        /* unfreeze user amount */
        userInfos[_user].wantFreeze -= _wantAmt ;
    } 

    /* withdraw
            condition
            * required _wantAmount > 0
            * user available balance must greater than request amount
     */
      function withdraw(uint256 _wantAmt) external payable nonReentrant returns(uint256){
        require(_wantAmt > 0, "_wantAmt <= 0");
        require(userInfos[msg.sender].want - userInfos[msg.sender].wantFreeze >= _wantAmt, "insufficient fund");
        /* calculate share require for withdraw */
        uint256 amount = _wantAmt *  (userInfos[msg.sender].share) / userInfos[msg.sender].want   ;
        /* withdraw from alpaca */
        IAlpacaLending(farmContractAddress).withdraw(amount);
        /* calculate bnb will get from withdraw*/
        uint256 bnb = amount.mul(IAlpacaLending(farmContractAddress).totalToken()).div(IAlpacaLending(farmContractAddress).totalSupply());
        /* update user pool*/
        userInfos[msg.sender].want -= _wantAmt;
        userInfos[msg.sender].share -= amount;
        /* reduce total share */
        shareLockedTotal = shareLockedTotal.sub(amount);
        /* developer get 50% interest share if interest > 0,transfer to user for request amount*/
        if(bnb > _wantAmt){
            uint256 interest = bnb-_wantAmt;
            payable(devAddress).transfer(interest.div(2));
            payable(msg.sender).transfer(bnb.sub(interest.div(2)));
            return (bnb);
        }
        payable(msg.sender).transfer(bnb);
        return (bnb);
    } 
    
    /* add user balance */
    function _addBalance(address _address,uint256 _wantAmt , uint256 _share) internal {
        userInfos[_address].want += _wantAmt;
        userInfos[_address].share += _share;
    }
    
    /* reassign market place contract */
    function reassignMP(address _marketPlaceContract) external {
        require(msg.sender == govAddress,"not allow");
        marketContractAddress = _marketPlaceContract;
    }
    fallback() external payable{}
}