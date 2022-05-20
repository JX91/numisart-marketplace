// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.3;
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
interface IStrategy{
    function directDeposit(uint256 _wantAmt,address _user,uint256 isFreeze) external payable;
    function lockFund(uint256 _wantAmt,address _user) external ;
    function unlockFund(uint256 _wantAmt,address _user) external ;
    function deposit(uint256 _wantAmt,address seller,uint256 _tokenId,address buyer,uint256 action,uint256 isFreeze,address _nftContract) external payable;
    function userInfos(address _user) external view returns(uint256,uint256,uint256);
}
contract PMGContract {

    enum Status { DEFAULT,LISTING,SOLD,DELIST,AUCTION,EXPIRE}

    struct listDetail{
        address seller;
        address cryptoToken;
        address nftContract;
        uint256 price;
        uint256 tokenId;
        Status status;
    }

    struct auctionDetail{
        address seller;
        address cryptoToken;
        address nftContract;
        uint256 price;
        uint256 tokenId;
        uint256 endTime;
        uint256 minBid;
        uint256 highestBid;
        address highestBidder;
        Status status;
    }

    struct offerDetail{
        address offerAddress;
        address cryptoToken;
        address nftContract;
        uint256 price;
        uint256 tokenId;
        uint256 endTime;
        bool isActive;
    }


    struct nftProfitSharing{
        address pioneer;
        address[10] exOwner;
        uint256 ownerCount;
    }

    mapping (address=>bool) public isTokenSupport;
    mapping (address=>address) public strategy;
    mapping (address=>bool) public isNFTSupport;
    mapping (address=>mapping(address=>mapping(uint256=>bool))) public userOfferId;
    mapping (uint256=>listDetail) public listItem;
    mapping (uint256=>mapping(address=>nftProfitSharing)) private nftProfit;
    mapping (uint256=>auctionDetail) public auctionItem;
    mapping (uint256=>offerDetail) public offerList;
    uint256 public listItemLength;
    uint256 public auctionItemLength;
    uint256 public offerItemLength;
    address owner;

    constructor(){
        owner=msg.sender;
        isNFTSupport[0xF2F74b394F79f235038B0cB1769c881eEe66a705] = true;
        isTokenSupport[0x734778123652973B37053c1b3CeD4256b2FEdbCb] = true; //telger
        isTokenSupport[0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d] = true; //usdc
        isTokenSupport[0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56] = true; //busd
        isTokenSupport[0xDfb1211E2694193df5765d54350e1145FD2404A1] = true; //wbnb
        isTokenSupport[0x2170Ed0880ac9A755fd29B2688956BD959F933F8] = true; //weth
        strategy[0x734778123652973B37053c1b3CeD4256b2FEdbCb] = 0x5D89AA42010dfB1F98F68b52AA4892AA42B13FF8;
    }
    modifier onlyOwner() {
        require(owner == msg.sender, "not owner");
        _;
    }

    event Listing(address indexed seller, uint256 itemId, address currencyAddress, address nftAddress, uint256 tokenId, uint256 amount);
    event Delist(uint indexed itemId);
    event BuyNFT(address indexed seller,address indexed buyer, uint256 itemId, address currencyAddress, address nftAddress, uint256 tokenId, uint256 amount);
    event NewOffer(address indexed buyer, address currencyAddress, address nftAddress, uint256 tokenId, uint256 offerId, uint256 amount, uint256 expiryTime);
    event CancelOffer(address indexed buyer, uint256 offerId);
    event AcceptOffer(address indexed seller, address indexed buyer, uint256 offerId);
    event Auction(address indexed seller, address currencyAddress, address nftAddress, uint256 minimumAmount,uint256 startingPrice, uint256 auctionId, uint256 tokenId, uint256 expiryTime);
    event Bid(address indexed buyer, address currencyAddress, uint256 bidAmount, uint256 auctionId );
    event AuctionEnd(address indexed buyer, uint256 auctionId);
    event AuctionRestart(uint256 auctionId,address currencyAddress, uint256 minimumAmount,uint256 startingPrice, uint256 expiryTime);
    event AuctionCancel(uint256 auctionId);

    /* add new support token */
    function addCoin(address _token) public onlyOwner {
        require(isTokenSupport[_token] == false,"token already support");
        isTokenSupport[_token] = true;
    }

    /* add new nft contract */
    function addNFT(address _token) public onlyOwner {
        require(isNFTSupport[_token] == false,"NFT already support");
        isNFTSupport[_token] = true;
    }

    /* edit support token strategy */
    function editStrategy(address _tokenContract,address _strategy) public onlyOwner  {
        require(isTokenSupport[_tokenContract] == true && strategy[_tokenContract] != _strategy,"token not supported | same strategy");
        strategy[_tokenContract] = _strategy;
    }


    /* list NFT
        condition
            * require listing address is owner of nft
            * require payment token is supported
            * require nft contract is supported
        increment list length,create list item detail and transfer nft from seller to marketplace
     */
    function listNFT(address _nftContract , address _tokenContract,uint256 _tokenId,uint256 _amount) public  {
        require(IERC721(_nftContract).ownerOf(_tokenId) == msg.sender,"not nft owner");
        require(isTokenSupport[_tokenContract],"payment token not support");
        require(isNFTSupport[_nftContract],"NFT not support");
        listItemLength+=1;
        listItem[listItemLength] =  listDetail( msg.sender,_tokenContract,_nftContract,_amount,_tokenId,Status.LISTING);
        IERC721(_nftContract).transferFrom(msg.sender,address(this),_tokenId);
        emit Listing(msg.sender, listItemLength, _tokenContract, _nftContract, _tokenId, _amount);
    }

    /* delist NFT
        condition
            * require delist address is seller
            * item status MUST be listing
        change status to delist and transfer back nft back to seller from market place
     */
    function delistNFT(uint256 _listItemId) public  {
        require(listItem[_listItemId].seller == msg.sender,"not nft seller");
        require(listItem[_listItemId].status == Status.LISTING,"invalid status");
        listItem[_listItemId].status =  Status.DELIST;
        IERC721(listItem[_listItemId].nftContract).transferFrom(address(this),msg.sender,listItem[_listItemId].tokenId);
        emit Delist(_listItemId);
    }

    /* buy NFT 
        condition 
            * require item status to be listing
            * buyer balance must be sufficient for pay
        1)get list item detail,update exOwner/pioneer info
        2)check avaible balance and freeze balance from strategy
        2a)transfer coin/token to pool if insufficient balance
        3)update related address pool balance and distribute the payment
        4)transfer nft to buyer 
    */
    function buyNFT(uint256 _index ) public payable {
        listDetail memory item = listItem[_index] ;
        require(item.status == Status.LISTING,"invalid status");
        nftProfitSharing  memory profit = nftProfit[item.tokenId][item.nftContract];
        listItem[_index].status = Status.SOLD;
        if(profit.pioneer == address(0)){
            nftProfit[item.tokenId][item.nftContract].pioneer = item.seller;
        }else if(profit.ownerCount<10){
            nftProfit[item.tokenId][item.nftContract].exOwner[profit.ownerCount] = (item.seller);
            nftProfit[item.tokenId][item.nftContract].ownerCount+=1;
        }
        (uint256 balance,uint256 freezeBalance,) = IStrategy(strategy[item.cryptoToken]).userInfos(msg.sender);
        if(item.cryptoToken == 0xDfb1211E2694193df5765d54350e1145FD2404A1){
            if(balance - freezeBalance< item.price){
                require(msg.value == item.price,"deposit bnb for bid");
                IStrategy(strategy[item.cryptoToken]).deposit{value:msg.value}(item.price  ,item.seller,item.tokenId,address(0),0,0,item.nftContract);
            }else{
                require(msg.value == 0,"no bnb deposit require");
                IStrategy(strategy[item.cryptoToken]).deposit(item.price  ,item.seller,item.tokenId,msg.sender,1,0,item.nftContract);
            }
        }else{
            if(balance - freezeBalance< item.price){
                require(IERC20(item.cryptoToken).balanceOf(msg.sender)>=item.price,"insufficient fund");
                IERC20(item.cryptoToken).transferFrom(msg.sender,address(this),item.price);
                IERC20(item.cryptoToken).approve(strategy[item.cryptoToken],item.price);
                IStrategy(strategy[item.cryptoToken]).deposit(item.price  ,item.seller,item.tokenId,address(0),0,0,item.nftContract);
            }else{
                IStrategy(strategy[item.cryptoToken]).deposit(item.price  ,item.seller,item.tokenId,msg.sender,1,0,item.nftContract);
            }
        }
        IERC721(item.nftContract).transferFrom(address(this),msg.sender,item.tokenId);
        
        emit BuyNFT(item.seller,msg.sender,_index,item.cryptoToken,item.nftContract,item.tokenId,item.price);
    }

    /* auction NFT
        condition 
            * require item owner is auction address
            * require payment token is supported
            * require nft contract is supported
            * auction period 0 < days < 7
        1)increment auction list length
        2)create auction detail
        3)transfer nft to market place
     */
    function auctionNFT(address _nftContract ,address _tokenContract,uint256 _tokenId,uint256 _price,uint256 _min_bid,uint256 _day) public  {
        require(IERC721(_nftContract).ownerOf(_tokenId) == msg.sender,"not nft owner");
        require(isTokenSupport[_tokenContract],"payment token not support");
        require(isNFTSupport[_nftContract],"nft contract not support");
        require(0 < _day && _day <= 7,"not support");
        auctionItemLength+=1;
        auctionItem[auctionItemLength] =  auctionDetail(msg.sender,_tokenContract,_nftContract,_price,_tokenId,block.timestamp+ (_day *  1 minutes) ,_min_bid,_price,address(0),Status.AUCTION);
        IERC721(_nftContract).transferFrom(msg.sender,address(this),_tokenId);
        emit Auction( msg.sender,  _tokenContract,  _nftContract,  _min_bid,_price,  auctionItemLength,  _tokenId,  block.timestamp+ (_day *  1 minutes));
    }

    /* bit auction NFT
        condition
            * require auction in valid time stamp
            * require bidder not initiator and previous highest bidder
            * require bid price >= previous highest bid + minimum bid and also multiply of minimum bid
            * require bidder wallet had sufficient balance
        bid auction item,unfreeze previous highest bidder fund and lock current bidder fund,update auction detail
     */
    function bidNFT(uint256 _auctionItemId,uint256 _price) public payable {
        // require(IERC721(nftContract).ownerOf(_tokenId) == msg.sender,"not nft owner");
        auctionDetail memory auctionitem = auctionItem[_auctionItemId];
        require (auctionitem.endTime>block.timestamp,"auction end");
        require (auctionitem.seller != msg.sender && auctionitem.highestBidder != msg.sender,"cannot bid on own auction | already highest bidder");
        require(_price >= auctionitem.highestBid+auctionitem.minBid && (_price - auctionitem.price)% auctionitem.minBid == 0,"invalid amount" );
        (uint256 balance,uint256 freezeBalance,) = IStrategy(strategy[auctionitem.cryptoToken]).userInfos(msg.sender);
        if(auctionitem.cryptoToken == 0xDfb1211E2694193df5765d54350e1145FD2404A1){
            if(balance - freezeBalance< _price){
                require(msg.value == _price,"deposit bnb for bid");
                IStrategy(strategy[auctionitem.cryptoToken]).directDeposit{value:_price}(_price,msg.sender,1);
            }else{
                require(msg.value == 0,"no bnb deposit require");
                IStrategy(strategy[auctionitem.cryptoToken]).lockFund(_price ,msg.sender);
            }
        }else{
            if(balance - freezeBalance< _price){
                require(IERC20(auctionitem.cryptoToken).balanceOf(msg.sender)>= _price,"insufficient fund");
                IERC20(auctionitem.cryptoToken).transferFrom(msg.sender,address(this),_price);
                IERC20(auctionitem.cryptoToken).approve(strategy[auctionitem.cryptoToken],_price);
                IStrategy(strategy[auctionitem.cryptoToken]).directDeposit(_price  ,msg.sender,1);
            }else{
                IStrategy(strategy[auctionitem.cryptoToken]).lockFund(_price ,msg.sender);
            }
        }
        
        if(auctionitem.highestBidder != address(0)){
            IStrategy(strategy[auctionitem.cryptoToken]).unlockFund(auctionitem.highestBid ,auctionitem.highestBidder);
        }
        
        auctionItem[_auctionItemId].highestBid = _price;
        auctionItem[_auctionItemId].highestBidder = msg.sender;
        
        emit Bid( msg.sender, auctionitem.cryptoToken, _price, _auctionItemId);
    }

    /* claim auction NFT
        condition
            * only seller or highest bidder can trigger
            * require auction end and status Auction
        1)get auction item detail
        2)get nft exOwner detail
        3)update auction status
        4)update exOwner
        5)distribute and update related address pool balance
        6)transfer nft to highest bidder
     */
    function claimAuctionNFT(uint256 _auctionItemId) public  {
        auctionDetail memory auctionitem = auctionItem[_auctionItemId];
        nftProfitSharing  memory profit = nftProfit[auctionitem.tokenId][auctionitem.nftContract];
        require(msg.sender == auctionitem.seller || msg.sender == auctionitem.highestBidder ,"unauthorized" );
        require (auctionitem.endTime<block.timestamp,"auction end");
        require( auctionitem.status == Status.AUCTION ,"invalid status" );
        auctionitem.status = Status.SOLD;
        if(profit.pioneer == address(0)){
            nftProfit[auctionitem.tokenId][auctionitem.nftContract].pioneer = auctionitem.seller;
        }else if(profit.ownerCount<10){
            nftProfit[auctionitem.tokenId][auctionitem.nftContract].exOwner[profit.ownerCount] = (auctionitem.seller);
            nftProfit[auctionitem.tokenId][auctionitem.nftContract].ownerCount+=1;
        }
        IStrategy(strategy[auctionitem.cryptoToken]).deposit(auctionitem.highestBid  ,auctionitem.seller,auctionitem.tokenId,auctionitem.highestBidder,1,1,auctionitem.nftContract);
        IERC721(auctionitem.nftContract).transferFrom(address(this),auctionitem.highestBidder,auctionitem.tokenId);
        emit AuctionEnd( auctionitem.highestBidder,  _auctionItemId);
    }

    /* restart or cancel auction
        condition
            * require auction end and status Auction
            * require no highest bidder on previous auction
            * require trigger address to be auction initiator
            * require payment token is supported
            * auction period 0 < days < 7
        1)get auction item detail
        1a)action 0 = cancel, action not equal 0 = restart
        2)update auction detail
        2a)set status to Expire if cancel
     */
    function auctionFail(uint256 _auctionItemId,uint256 _action,uint256 _price,uint256 _min_bid,uint256 _day ,address _tokenContract) public {
        auctionDetail memory auctionitem = auctionItem[_auctionItemId];
        require(msg.sender == auctionitem.seller ,"unauthorized" );
        require(isTokenSupport[_tokenContract],"payment token not support");
        require( auctionitem.status == Status.AUCTION &&  block.timestamp > auctionitem.endTime ,"invalid status" );
        require( auctionitem.highestBidder == address(0),"auction had a winner" );
        if(_action == 0){
            IERC721(auctionitem.nftContract).transferFrom(address(this),msg.sender,auctionitem.tokenId);
            auctionItem[_auctionItemId].status = Status.EXPIRE;
            emit AuctionCancel( _auctionItemId);
            return ;
        }
        
        auctionItem[_auctionItemId].minBid = _min_bid;
        auctionItem[_auctionItemId].price = _price;
        auctionItem[_auctionItemId].highestBid = _price;
        auctionItem[_auctionItemId].cryptoToken = _tokenContract;
        auctionItem[_auctionItemId].endTime = block.timestamp+ (_day *  1 minutes);
        emit AuctionRestart(_auctionItemId,_tokenContract, _min_bid,_price, block.timestamp+ (_day *  1 minutes));
        return ;   
    }

    /* offer NFT
        condition
            * require payment token is supported
            * require nft contract is supported
            * require user not offer this nft before
        1)update offer list length
        2)lock user pool balance
        2a)deposit fund to pool if pool balance insufficient
        3)set offer valid time
        4)create offer item
        5)update user offer nft status
     */
    function offerNFT(address _tokenContract,address _nftContract,uint256 _tokenId,uint256 _price) public payable  {
        /*  need to offer the NFT */
        require(isTokenSupport[_tokenContract],"payment token not support");
        require(isNFTSupport[_nftContract],"nft contract not support");
        require(userOfferId[msg.sender][_nftContract][_tokenId]==false,"User offer this nft before");
        offerItemLength+=1;
        (uint256 balance,uint256 freezeBalance,) = IStrategy(strategy[_tokenContract]).userInfos(msg.sender);
        if(_tokenContract == 0xDfb1211E2694193df5765d54350e1145FD2404A1){
            if(balance - freezeBalance< _price){
                require(msg.value == _price,"deposit bnb for bid");
                IStrategy(strategy[_tokenContract]).directDeposit{value:msg.value}(_price  ,msg.sender,1);
            }else{
                require(msg.value == 0,"no bnb deposit require");
                IStrategy(strategy[_tokenContract]).lockFund(_price ,msg.sender);
            }
        }else{
            if(balance - freezeBalance< _price){
                require(IERC20(_tokenContract).balanceOf(msg.sender)>= _price,"insufficient fund");
                IERC20(_tokenContract).transferFrom(msg.sender,address(this),_price);
                IERC20(_tokenContract).approve(strategy[_tokenContract],_price);
                IStrategy(strategy[_tokenContract]).directDeposit{value:msg.value}(_price  ,msg.sender,1);
            }else{
                IStrategy(strategy[_tokenContract]).lockFund(_price ,msg.sender);
            }
        }
        
        uint256 endTime = block.timestamp + 5 minutes ;
        offerList[offerItemLength]= offerDetail(msg.sender,_tokenContract,_nftContract,_price,_tokenId,endTime,true);
        userOfferId[msg.sender][_nftContract][_tokenId] = true;
        emit NewOffer(  msg.sender ,  _tokenContract,  _nftContract,  _tokenId,  offerItemLength,  _price,  endTime);
    }

    /* cancel offer NFT and claim
        condition
            * require user offer this nft before
        1)update offer item status
        2)unlock user pool balance
        3)update user offer nft status
     */
    function cancelOfferAndClaim(uint256 _offerId) public {
        require(userOfferId[msg.sender][offerList[_offerId].nftContract][offerList[_offerId].tokenId]==true,"Invalid offer");
        offerList[_offerId].isActive = false;
        IStrategy(strategy[offerList[_offerId].cryptoToken]).unlockFund(offerList[_offerId].price ,msg.sender);
        userOfferId[msg.sender][offerList[_offerId].nftContract][offerList[_offerId].tokenId] = false;
        emit CancelOffer(msg.sender, _offerId);
    }

    /*  accept offer 
        condition
            * require user is current owner(nft cant be auction and list)
            * require offer not end
            * require offer status is valid
        1)get offer item detail
        2)get exOwner detail
        3)update exOwner
        4)distribute and update related address pool balance 
        5)update offer status
    */
    function acceptOffer(uint256 _offerId) public  {
        offerDetail memory offerdetail = offerList[_offerId];
        nftProfitSharing  memory profit = nftProfit[offerdetail.tokenId][offerdetail.nftContract];
        address  own = IERC721(offerdetail.nftContract).ownerOf(offerdetail.tokenId);
        require(offerdetail.isActive==true,"offer invalid");
        require(offerdetail.endTime<block.timestamp,"offer expired");
        require(own == msg.sender ,"not owner now");
        if(profit.pioneer == address(0)){
            nftProfit[offerdetail.tokenId][offerdetail.nftContract].pioneer = msg.sender;
        }else if(profit.ownerCount<10){
            nftProfit[offerdetail.tokenId][offerdetail.nftContract].exOwner[profit.ownerCount] = (msg.sender);
            nftProfit[offerdetail.tokenId][offerdetail.nftContract].ownerCount+=1;
        }
        IERC721(offerdetail.nftContract).transferFrom(msg.sender,offerdetail.offerAddress,offerdetail.tokenId);
        IStrategy(strategy[offerdetail.cryptoToken]).deposit(offerdetail.price  ,msg.sender,offerdetail.tokenId,offerdetail.offerAddress,1,1,offerdetail.nftContract);
        offerList[_offerId].isActive = false;
        emit AcceptOffer(msg.sender, offerdetail.offerAddress, _offerId);
    }

    /*  direct deposit to pool
        condition
            * require payment token is supported
            * require user balance must be sufficient for deposit
        1)deposit to pool
        1a)give approve to pool if token transfer
    */
    function deposit(address _tokenContract,uint256 _amount) public payable {
        require(isTokenSupport[_tokenContract]==true,"token contract not support");
        if(_tokenContract == 0xDfb1211E2694193df5765d54350e1145FD2404A1){
            require((msg.sender).balance>= _amount,"insufficient fund");
            IStrategy(strategy[_tokenContract]).directDeposit{value:msg.value}(msg.value ,msg.sender,0);
        }else{
            require(IERC20(_tokenContract).balanceOf(msg.sender) >= _amount,"insufficient fund");
            IERC20(_tokenContract).approve(strategy[_tokenContract],_amount);
            IERC20(_tokenContract).transferFrom(msg.sender,address(this),_amount);
            IStrategy(strategy[_tokenContract]).directDeposit(_amount ,msg.sender,0);
        }
    }

    /* nftExOwnerDetail */
    function nftProfitDetail(uint256 _tokenId,address _nftContract) public view returns (nftProfitSharing memory)  {
        return nftProfit[_tokenId][_nftContract];
    }

    /* for staging use */
    function claimNFT(uint256 _tokenId) public {
        IERC721(0xF2F74b394F79f235038B0cB1769c881eEe66a705).transferFrom(address(this),msg.sender,_tokenId);
    }
} 