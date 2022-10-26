// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "./interfaces/IToken.sol";

contract Card is VRFConsumerBaseV2, ConfirmedOwner {
    
    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
        uint256 cardId;
        uint256 tokenAmount;
    }
    
    struct CardInfo {
        uint256 timestamp;
        uint256 cardId;
        uint256 cardPower;
        bool forSale;
        uint256 cardPrice;
    }

    using Counters for Counters.Counter;

    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event Created(address indexed from, uint256 indexed cardId, uint256 amount);
    event Banished(address indexed to, uint256 indexed cardId, uint256 amount);
    event Listed(address indexed from, uint256 indexed cardId, uint256 cardPrice);
    event Purchased(address indexed from, address indexed to, uint256 indexed cardId, uint256 cardPrice);

    uint8[4] public symbols = [0, 2, 4, 7];
    IToken public token;
    Counters.Counter private currentCardId;
    mapping(address => mapping(uint256 => CardInfo)) private cards;
    mapping(uint256 => address) private owners;
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    VRFCoordinatorV2Interface COORDINATOR;

    // Your subscription ID.
    uint64 s_subscriptionId;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // Goerli 30 gwei Key Hash
    bytes32 keyHash =
        0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    // Have to calculate something in callback function so set it 1M
    uint32 callbackGasLimit = 1_000_000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 4;

    /**
     * COORDINATOR Address FOR GOERLI: 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
     */
    constructor(uint64 _subscriptionId, address _coordinatorAddress, address _token)
        VRFConsumerBaseV2(_coordinatorAddress)
        ConfirmedOwner(msg.sender)
    {
        token = IToken(_token);
        COORDINATOR = VRFCoordinatorV2Interface(_coordinatorAddress);
        s_subscriptionId = _subscriptionId;
    }

    /// @dev Assumes the subscription is funded sufficiently.
    function createCard(uint256 _amount)
        external
        returns (uint256 requestId)
    {
        require(_amount > 0, "Amount must be greater than 0");
        currentCardId.increment();
        owners[currentCardId.current()] = msg.sender;
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false,
            cardId: currentCardId.current(),
            tokenAmount: _amount
        });
        requestIds.push(requestId);
        lastRequestId = requestId;

        token.transferFrom(msg.sender, address(this), _amount);

        emit Created(msg.sender, currentCardId.current(), _amount);
        return requestId;
    }

    function banishCard(uint256 _cardId) external {
        CardInfo storage cardInfo = cards[msg.sender][_cardId];
        require(cardInfo.cardId == _cardId, "Card ID is wrong");
        
        uint256 amount = cardInfo.cardPower * 100 * ((block.timestamp - cardInfo.timestamp) / 1 days + 1);
        require(token.balanceOf(address(this)) >= amount, "Insufficient token amount");

        token.transfer(msg.sender, amount);
        
        delete owners[_cardId];
        delete cards[msg.sender][_cardId];

        emit Banished(msg.sender, _cardId, amount);
    }

    /**
     * @dev Lists a card on the third-party marketplace
     */
    function listCard(uint256 _cardId, uint256 _cardPrice) external {
        CardInfo storage cardInfo = cards[msg.sender][_cardId];
        require(cardInfo.cardId == _cardId, "Card ID is wrong");

        cardInfo.forSale = true;
        cardInfo.cardPrice = _cardPrice;

        emit Listed(msg.sender, _cardId, _cardPrice);
    }

    /**
     * @dev Purchase a card listed on the third-party marketplace
     */
    function buyCard(uint256 _cardId) external {
        address seller = owners[_cardId];
        require(seller != address(0), "Card ID is wrong");
        
        CardInfo storage cardInfo = cards[seller][_cardId];
        require(cardInfo.forSale && cardInfo.cardPrice > 0, "This card is not for sale");

        cards[msg.sender][_cardId] = cardInfo;
        cards[msg.sender][_cardId].forSale = false;
        delete cards[seller][_cardId];
        owners[_cardId] = msg.sender;
        token.transferFrom(msg.sender, seller, cards[msg.sender][_cardId].cardPrice);

        emit Purchased(seller, msg.sender, _cardId, cards[msg.sender][_cardId].cardPrice);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        uint256 cardId = s_requests[_requestId].cardId;
        uint256 tokenAmount = s_requests[_requestId].tokenAmount;
        cards[msg.sender][cardId] = CardInfo(
            uint64(block.timestamp),
            cardId,
            _randomWords[3] * (tokenAmount * (_randomWords[2] + _randomWords[0] + symbols[_randomWords[1]-1])) / 100,
            false,
            0
        );
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(uint256 _requestId)
        external
        view
        returns (bool fulfilled, uint256[] memory randomWords)
    {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }
}
