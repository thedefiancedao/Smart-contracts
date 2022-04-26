//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @author Avo Labs GmbH
contract DePlayground {
    mapping(address => mapping(uint256 => Auction)) public pretokenContractAuctions;
    mapping(address => uint256) failedTransferCredits;

    struct Auction {
        //map token ID to
        uint32 bidIncreasePercentage;
        uint32 auctionBidPeriod; //Increments the length of time the auction is open in which a new bid can be made after each bid.
        uint64 auctionEnd;
        uint128 minPrice;
        uint128 buyNowPrice;
        uint128 HighestBid;
        address HighestBidder;
        address Seller;
        uint256 amount;
        address whitelistedBuyer; //The seller can specify a whitelisted address for a sale (this is effectively a direct sale).
        address Recipient; //The bidder can specify a recipient for the pretokens if their bid is successful.
        address ERC20Token; // The seller can specify an ERC20 token that can be used to bid or purchase the pretokens.
        address[] feeRecipients;
        uint32[] feePercentages;
    }

    uint32 public defaultBidIncreasePercentage;
    uint32 public minimumSettableIncreasePercentage;
    uint32 public maximumMinPricePercentage;
    uint32 public defaultAuctionBidPeriod;

    /*╔═════════════════════════════╗
      ║           EVENTS            ║
      ╚═════════════════════════════╝*/

    event AuctionCreated(
        address preToken,
        uint256 amount,
        address Seller,
        address erc20Token,
        uint128 minPrice,
        uint128 buyNowPrice,
        uint32 auctionBidPeriod,
        uint32 bidIncreasePercentage,
        address[] feeRecipients,
        uint32[] feePercentages
    );

    event SaleCreated(
        address preToken,
        uint256 amount,
        address Seller,
        address erc20Token,
        uint128 buyNowPrice,
        address whitelistedBuyer,
        address[] feeRecipients,
        uint32[] feePercentages
    );

    event BidMade(
        address preToken,
        uint256 amount,
        address bidder,
        uint256 ethAmount,
        address erc20Token,
        uint256 tokenAmount
    );

    event AuctionPeriodUpdated(
        address preToken,
        uint256 amount,
        uint64 auctionEndPeriod
    );

    event TransferredAndSellerPaid(
        address preToken,
        uint256 amount,
        address Seller,
        uint128 HighestBid,
        address HighestBidder,
        address Recipient
    );

    event AuctionSettled(
        address preToken,
        uint256 amount,
        address auctionSettler
    );

    event AuctionWithdrawn(
        address preToken,
        uint256 amount,
        address Owner
    );

    event BidWithdrawn(
        address preToken,
        uint256 amount,
        address highestBidder
    );

    event WhitelistedBuyerUpdated(
        address preToken,
        uint256 amount,
        address newWhitelistedBuyer
    );

    event MinimumPriceUpdated(
        address preToken,
        uint256 amount,
        uint256 newMinPrice
    );

    event BuyNowPriceUpdated(
        address preToken,
        uint256 amount,
        uint128 newBuyNowPrice
    );
    event HighestBidTaken(address preToken, uint256 amount);
    /**********************************/
    /*╔═════════════════════════════╗
      ║             END             ║
      ║            EVENTS           ║
      ╚═════════════════════════════╝*/
    /**********************************/
    /*╔═════════════════════════════╗
      ║          MODIFIERS          ║
      ╚═════════════════════════════╝*/

    modifier isAuctionNotStartedByOwner(
        address _preToken,
        uint256 _amount
    ) {
        require(
            pretokenContractAuctions[_preToken][_amount].Seller !=
                msg.sender,
            "Auction already started by owner"
        );

        if (
            pretokenContractAuctions[_preToken][_amount].Seller !=
            address(0)
        ) {
            require(
                msg.sender == IERC20(_preToken).ownerOf(_amount),
                "Sender doesn't own Pretoken"
            );

            _resetAuction(_preToken, _amount);
        }
        _;
    }

    modifier auctionOngoing(address _preToken, uint256 _amount) {
        require(
            _isAuctionOngoing(_preToken, _amount),
            "Auction has ended"
        );
        _;
    }

    modifier priceGreaterThanZero(uint256 _price) {
        require(_price > 0, "Price cannot be 0");
        _;
    }
    /*
     * The minimum price must be 80% of the buyNowPrice(if set).
     */
    modifier minPriceDoesNotExceedLimit(
        uint128 _buyNowPrice,
        uint128 _minPrice
    ) {
        require(
            _buyNowPrice == 0 ||
                _getPortionOfBid(_buyNowPrice, maximumMinPricePercentage) >=
                _minPrice,
            "MinPrice > 80% of buyNowPrice"
        );
        _;
    }

    modifier notSeller(address _preToken, uint256 _amount) {
        require(
            msg.sender !=
                pretokenContractAuctions[_preToken][_amount].Seller,
            "Owner cannot bid on own Pretoken"
        );
        _;
    }
    modifier onlySeller(address _preToken, uint256 _amount) {
        require(
            msg.sender ==
                pretokenContractAuctions[_preToken][_amount].Seller,
            "Only Pretoken seller"
        );
        _;
    }
    /*
     * The bid amount was either equal the buyNowPrice or it must be higher than the previous
     * bid by the specified bid increase percentage.
     */
    modifier bidAmountMeetsBidRequirements(
        address _preToken,
        uint256 _amount,
        uint128 _tokenAmount
    ) {
        require(
            _doesBidMeetBidRequirements(
                _preToken,
                _amount,
                _tokenAmount
            ),
            "Not enough funds to bid on pretokens"
        );
        _;
    }
    // check if the highest bidder can purchase this pretoken.
    modifier onlyApplicableBuyer(
        address _preToken,
        uint256 _amount
    ) {
        require(
            !_isWhitelistedSale(_preToken, _amount) ||
                pretokenContractAuctions[_preToken][_amount]
                    .whitelistedBuyer ==
                msg.sender,
            "Only the whitelisted buyer"
        );
        _;
    }

    modifier minimumBidNotMade(address _preToken, uint256 _amount) {
        require(
            !_isMinimumBidMade(_preToken, _amount),
            "The auction has a valid bid made"
        );
        _;
    }

    /*
     * Payment is accepted if the payment is made in the ERC20 token or ETH specified by the seller.
     * Early bids on pretokens not yet up for auction must be made in ETH.
     */
    modifier paymentAccepted(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _tokenAmount
    ) {
        require(
            _isPaymentAccepted(
                _preToken,
                _amount,
                _erc20Token,
                _tokenAmount
            ),
            "Bid to be in specified ERC20/Eth"
        );
        _;
    }

    modifier isAuctionOver(address _preToken, uint256 _amount) {
        require(
            !_isAuctionOngoing(_preToken, _amount),
            "Auction is not yet over"
        );
        _;
    }

    modifier notZeroAddress(address _address) {
        require(_address != address(0), "Cannot specify 0 address");
        _;
    }

    modifier increasePercentageAboveMinimum(uint32 _bidIncreasePercentage) {
        require(
            _bidIncreasePercentage >= minimumSettableIncreasePercentage,
            "Bid increase percentage too low"
        );
        _;
    }

    modifier isFeePercentagesLessThanMaximum(uint32[] memory _feePercentages) {
        uint32 totalPercent;
        for (uint256 i = 0; i < _feePercentages.length; i++) {
            totalPercent = totalPercent + _feePercentages[i];
        }
        require(totalPercent <= 10000, "Fee percentages exceed maximum");
        _;
    }

    modifier correctFeeRecipientsAndPercentages(
        uint256 _recipientsLength,
        uint256 _percentagesLength
    ) {
        require(
            _recipientsLength == _percentagesLength,
            "Recipients != percentages"
        );
        _;
    }

    modifier isNotASale(address _preToken, uint256 _amount) {
        require(
            !_isASale(_preToken, _amount),
            "Not applicable for a sale"
        );
        _;
    }

    /**********************************/
    /*╔═════════════════════════════╗
      ║             END             ║
      ║          MODIFIERS          ║
      ╚═════════════════════════════╝*/
    /**********************************/
    // constructor
    constructor() {
        defaultBidIncreasePercentage = 100;
        defaultAuctionBidPeriod = 86400; //1 day
        minimumSettableIncreasePercentage = 100;
        maximumMinPricePercentage = 8000;
    }

    /*╔══════════════════════════════╗
      ║    AUCTION CHECK FUNCTIONS   ║
      ╚══════════════════════════════╝*/
    function _isAuctionOngoing(address _preToken, uint256 _amount)
        internal
        view
        returns (bool)
    {
        uint64 auctionEndTimestamp = pretokenContractAuctions[_preToken][
            _amount
        ].auctionEnd;
        //if the auctionEnd is set to 0, the auction is technically on-going, however
        //the minimum bid price (minPrice) has not yet been met.
        return (auctionEndTimestamp == 0 ||
            block.timestamp < auctionEndTimestamp);
    }

    /*
     * Check if a bid has been made. This is applicable in the early bid scenario
     * to ensure that if an auction is created after an early bid, the auction
     * begins appropriately or is settled if the buy now price is met.
     */
    function _isABidMade(address _preToken, uint256 _amount)
        internal
        view
        returns (bool)
    {
        return (pretokenContractAuctions[_preToken][_amount]
            .HighestBid > 0);
    }

    /*
     *if the minPrice is set by the seller, check that the highest bid meets or exceeds that price.
     */
    function _isMinimumBidMade(address _preToken, uint256 _amount)
        internal
        view
        returns (bool)
    {
        uint128 minPrice = pretokenContractAuctions[_preToken][_amount]
            .minPrice;
        return
            minPrice > 0 &&
            (pretokenContractAuctions[_preToken][_amount].HighestBid >=
                minPrice);
    }

    /*
     * If the buy now price is set by the seller, check that the highest bid meets that price.
     */
    function _isBuyNowPriceMet(address _preToken, uint256 _amount)
        internal
        view
        returns (bool)
    {
        uint128 buyNowPrice = pretokenContractAuctions[_preToken][_amount]
            .buyNowPrice;
        return
            buyNowPrice > 0 &&
            pretokenContractAuctions[_preToken][_amount].HighestBid >=
            buyNowPrice;
    }

    /*
     * Check that a bid is applicable for the purchase of the pretoken.
     * In the case of a sale: the bid needs to meet the buyNowPrice.
     * In the case of an auction: the bid needs to be a % higher than the previous bid.
     */
    function _doesBidMeetBidRequirements(
        address _preToken,
        uint256 _amount,
        uint128 _tokenAmount
    ) internal view returns (bool) {
        uint128 buyNowPrice = pretokenContractAuctions[_preToken][_amount]
            .buyNowPrice;
        //if buyNowPrice is met, ignore increase percentage
        if (
            buyNowPrice > 0 &&
            (msg.value >= buyNowPrice || _tokenAmount >= buyNowPrice)
        ) {
            return true;
        }
        //if the pretoken is up for auction, the bid needs to be a % higher than the previous bid
        uint256 bidIncreaseAmount = (pretokenContractAuctions[_preToken][
            _amount
        ].HighestBid *
            (10000 +
                _getBidIncreasePercentage(_preToken, _amount))) /
            10000;
        return (msg.value >= bidIncreaseAmount ||
            _tokenAmount >= bidIncreaseAmount);
    }

    /*
     * An Pretoken is up for sale if the buyNowPrice is set, but the minPrice is not set.
     * Therefore the only way to conclude the Pretoken sale is to meet the buyNowPrice.
     */
    function _isASale(address _preToken, uint256 _amount)
        internal
        view
        returns (bool)
    {
        return (pretokenContractAuctions[_preToken][_amount].buyNowPrice >
            0 &&
            pretokenContractAuctions[_preToken][_amount].minPrice == 0);
    }

    function _isWhitelistedSale(address _preToken, uint256 _amount)
        internal
        view
        returns (bool)
    {
        return (pretokenContractAuctions[_preToken][_amount]
            .whitelistedBuyer != address(0));
    }

    /*
     * The highest bidder is allowed to purchase the pretoken if
     * no whitelisted buyer is set by the pretoken seller.
     * Otherwise, the highest bidder must equal the whitelisted buyer.
     */
    function _isHighestBidderAllowedToPurchasePreToken(
        address _preToken,
        uint256 _amount
    ) internal view returns (bool) {
        return
            (!_isWhitelistedSale(_preToken, _amount)) ||
            _isHighestBidderWhitelisted(_preToken, _amount);
    }

    function _isHighestBidderWhitelisted(
        address _preToken,
        uint256 _amount
    ) internal view returns (bool) {
        return (pretokenContractAuctions[_preToken][_amount]
            .HighestBidder ==
            pretokenContractAuctions[_preToken][_amount]
                .whitelistedBuyer);
    }


    function _isPaymentAccepted(
        address _preToken,
        uint256 _amount,
        address _bidERC20Token,
        uint128 _tokenAmount
    ) internal view returns (bool) {
        address auctionERC20Token = pretokenContractAuctions[_preToken][
            _amount
        ].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            return
                msg.value == 0 &&
                auctionERC20Token == _bidERC20Token &&
                _tokenAmount > 0;
        } else {
            return
                msg.value != 0 &&
                _bidERC20Token == address(0) &&
                _tokenAmount == 0;
        }
    }

    function _isERC20Auction(address _auctionERC20Token)
        internal
        pure
        returns (bool)
    {
        return _auctionERC20Token != address(0);
    }

    /*
     * Returns the percentage of the total bid (used to calculate fee payments)
     */
    function _getPortionOfBid(uint256 _totalBid, uint256 _percentage)
        internal
        pure
        returns (uint256)
    {
        return (_totalBid * (_percentage)) / 10000;
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║    AUCTION CHECK FUNCTIONS   ║
      ╚══════════════════════════════╝*/
    /**********************************/
    /*╔══════════════════════════════╗
      ║    DEFAULT GETTER FUNCTIONS  ║
      ╚══════════════════════════════╝*/
    /*****************************************************************
     * These functions check if the applicable auction parameter has *
     * been set by the Pretoken seller. If not, return the default value. *
     *****************************************************************/

    function _getBidIncreasePercentage(
        address _preToken,
        uint256 _amount
    ) internal view returns (uint32) {
        uint32 bidIncreasePercentage = pretokenContractAuctions[_preToken][
            _amount
        ].bidIncreasePercentage;

        if (bidIncreasePercentage == 0) {
            return defaultBidIncreasePercentage;
        } else {
            return bidIncreasePercentage;
        }
    }

    function _getAuctionBidPeriod(address _preToken, uint256 _amount)
        internal
        view
        returns (uint32)
    {
        uint32 auctionBidPeriod = pretokenContractAuctions[_preToken][
            _amount
        ].auctionBidPeriod;

        if (auctionBidPeriod == 0) {
            return defaultAuctionBidPeriod;
        } else {
            return auctionBidPeriod;
        }
    }

    /*
     * The default value for the Pretoken recipient is the highest bidder
     */
    function _getPretokenRecipient(address _preToken, uint256 _amount)
        internal
        view
        returns (address)
    {
        address Recipient = pretokenContractAuctions[_preToken][
            _amount
        ].Recipient;

        if (Recipient == address(0)) {
            return
                pretokenContractAuctions[_preToken][_amount]
                    .HighestBidder;
        } else {
            return Recipient;
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║    DEFAULT GETTER FUNCTIONS  ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║  TRANSFER PRETOKENS TO CONTRACT   ║
      ╚══════════════════════════════╝*/
    function _transferPretokenToAuctionContract(
        address _preToken,
        uint256 _amount
    ) internal {
        address _Seller = pretokenContractAuctions[_preToken][_amount]
            .Seller;
        if (IERC20(_preToken).ownerOf(_amount) == _Seller) {
            IERC20(_preToken).transferFrom(
                _Seller,
                address(this),
                _amount
            );
            require(
                IERC20(_preToken).ownerOf(_amount) == address(this),
                "Pretoken transfer failed"
            );
        } else {
            require(
                IERC20(_preToken).ownerOf(_amount) == address(this),
                "Seller doesn't own Pretokens"
            );
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║  TRANSFER PRETOKENS TO CONTRACT   ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       AUCTION CREATION       ║
      ╚══════════════════════════════╝*/

    function _setupAuction(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        internal
        minPriceDoesNotExceedLimit(_buyNowPrice, _minPrice)
        correctFeeRecipientsAndPercentages(
            _feeRecipients.length,
            _feePercentages.length
        )
        isFeePercentagesLessThanMaximum(_feePercentages)
    {
        if (_erc20Token != address(0)) {
            pretokenContractAuctions[_preToken][_amount]
                .ERC20Token = _erc20Token;
        }
        pretokenContractAuctions[_preToken][_amount]
            .feeRecipients = _feeRecipients;
        pretokenContractAuctions[_preToken][_amount]
            .feePercentages = _feePercentages;
        pretokenContractAuctions[_preToken][_amount]
            .buyNowPrice = _buyNowPrice;
        pretokenContractAuctions[_preToken][_amount].minPrice = _minPrice;
        pretokenContractAuctions[_preToken][_amount].Seller = msg
            .sender;
    }

    function _createNewPretokenAuction(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    ) internal {
        // Sending the Pretoken to this contract
        _setupAuction(
            _preToken,
            _amount,
            _erc20Token,
            _minPrice,
            _buyNowPrice,
            _feeRecipients,
            _feePercentages
        );
        emit PretokenAuctionCreated(
            _preToken,
            _amount,
            msg.sender,
            _erc20Token,
            _minPrice,
            _buyNowPrice,
            _getAuctionBidPeriod(_preToken, _amount),
            _getBidIncreasePercentage(_preToken, _amount),
            _feeRecipients,
            _feePercentages
        );
        _updateOngoingAuction(_preToken, _amount);
    }

    /**
     * Create an auction that uses the default bid increase percentage
     * & the default auction bid period.
     */
    function createDefaultPretokenAuction(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        isAuctionNotStartedByOwner(_preToken, _amount)
        priceGreaterThanZero(_minPrice)
    {
        _createNewPretokenAuction(
            _preToken,
            _amount,
            _erc20Token,
            _minPrice,
            _buyNowPrice,
            _feeRecipients,
            _feePercentages
        );
    }

    function createNewPretokenAuction(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _minPrice,
        uint128 _buyNowPrice,
        uint32 _auctionBidPeriod, //this is the time that the auction lasts until another bid occurs
        uint32 _bidIncreasePercentage,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        isAuctionNotStartedByOwner(_preToken, _amount)
        priceGreaterThanZero(_minPrice)
        increasePercentageAboveMinimum(_bidIncreasePercentage)
    {
        pretokenContractAuctions[_preToken][_amount]
            .auctionBidPeriod = _auctionBidPeriod;
        pretokenContractAuctions[_preToken][_amount]
            .bidIncreasePercentage = _bidIncreasePercentage;
        _createNewPretokenAuction(
            _preToken,
            _amount,
            _erc20Token,
            _minPrice,
            _buyNowPrice,
            _feeRecipients,
            _feePercentages
        );
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       AUCTION CREATION       ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║            SALES             ║
      ╚══════════════════════════════╝*/

    /********************************************************************
     * Allows for a standard sale mechanism where the Pretoken seller can    *
     * can select an address to be whitelisted. This address is then    *
     * allowed to make a bid on the Pretoken. No other address can bid on    *
     * the Pretoken.                                                         *
     ********************************************************************/
    function _setupSale(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _buyNowPrice,
        address _whitelistedBuyer,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        internal
        correctFeeRecipientsAndPercentages(
            _feeRecipients.length,
            _feePercentages.length
        )
        isFeePercentagesLessThanMaximum(_feePercentages)
    {
        if (_erc20Token != address(0)) {
            pretokenContractAuctions[_preToken][_amount]
                .ERC20Token = _erc20Token;
        }
        pretokenContractAuctions[_preToken][_amount]
            .feeRecipients = _feeRecipients;
        pretokenContractAuctions[_preToken][_amount]
            .feePercentages = _feePercentages;
        pretokenContractAuctions[_preToken][_amount]
            .buyNowPrice = _buyNowPrice;
        pretokenContractAuctions[_preToken][_amount]
            .whitelistedBuyer = _whitelistedBuyer;
        pretokenContractAuctions[_preToken][_amount].Seller = msg
            .sender;
    }

    function createSale(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _buyNowPrice,
        address _whitelistedBuyer,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        isAuctionNotStartedByOwner(_preToken, _amount)
        priceGreaterThanZero(_buyNowPrice)
    {
        //min price = 0
        _setupSale(
            _preToken,
            _amount,
            _erc20Token,
            _buyNowPrice,
            _whitelistedBuyer,
            _feeRecipients,
            _feePercentages
        );

        emit SaleCreated(
            _preToken,
            _amount,
            msg.sender,
            _erc20Token,
            _buyNowPrice,
            _whitelistedBuyer,
            _feeRecipients,
            _feePercentages
        );
        //check if buyNowPrice is meet and conclude sale, otherwise reverse the early bid
        if (_isABidMade(_preToken, _amount)) {
            if (
                //we only revert the underbid if the seller specifies a different
                //whitelisted buyer to the highest bidder
                _isHighestBidderAllowedToPurchasePretoken(
                    _preToken,
                    _amount
                )
            ) {
                if (_isBuyNowPriceMet(_preToken, _amount)) {
                    _transferPretokenToAuctionContract(
                        _preToken,
                        _amount
                    );
                    _transferPretokenAndPaySeller(_preToken, _amount);
                }
            } else {
                _reverseAndResetPreviousBid(_preToken, _amount);
            }
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║            SALES             ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔═════════════════════════════╗
      ║        BID FUNCTIONS        ║
      ╚═════════════════════════════╝*/

    /********************************************************************
     * Make bids with ETH or an ERC20 Token specified by the Pretoken seller.*
     * Additionally, a buyer can pay the asking price to conclude a sale*
     * of an Pretoken.                                                      *
     ********************************************************************/

    function _makeBid(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _tokenAmount
    )
        internal
        notSeller(_preToken, _amount)
        paymentAccepted(
            _preToken,
            _amount,
            _erc20Token,
            _tokenAmount
        )
        bidAmountMeetsBidRequirements(
            _preToken,
            _amount,
            _tokenAmount
        )
    {
        _reversePreviousBidAndUpdateHighestBid(
            _preToken,
            _amount,
            _tokenAmount
        );
        emit BidMade(
            _preToken,
            _amount,
            msg.sender,
            msg.value,
            _erc20Token,
            _tokenAmount
        );
        _updateOngoingAuction(_preToken, _amount);
    }

    function makeBid(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _tokenAmount
    )
        external
        payable
        auctionOngoing(_preToken, _amount)
        onlyApplicableBuyer(_preToken, _amount)
    {
        _makeBid(_preToken, _amount, _erc20Token, _tokenAmount);
    }

    function makeCustomBid(
        address _preToken,
        uint256 _amount,
        address _erc20Token,
        uint128 _tokenAmount,
        address _Recipient
    )
        external
        payable
        auctionOngoing(_preToken, _amount)
        notZeroAddress(_Recipient)
        onlyApplicableBuyer(_preToken, _amount)
    {
        pretokenContractAuctions[_preToken][_amount]
            .Recipient = _Recipient;
        _makeBid(_preToken, _amount, _erc20Token, _tokenAmount);
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║        BID FUNCTIONS         ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/

    /***************************************************************
     * Settle an auction or sale if the buyNowPrice is met or set  *
     *  auction period to begin if the minimum price has been met. *
     ***************************************************************/
    function _updateOngoingAuction(
        address _preToken,
        uint256 _amount
    ) internal {
        if (_isBuyNowPriceMet(_preToken, _amount)) {
            _transferPretokenToAuctionContract(_preToken, _amount);
            _transferPretokenAndPaySeller(_preToken, _amount);
            return;
        }
        //min price not set, pretoken not up for auction yet
        if (_isMinimumBidMade(_preToken, _amount)) {
            _transferPretokenToAuctionContract(_preToken, _amount);
            _updateAuctionEnd(_preToken, _amount);
        }
    }

    function _updateAuctionEnd(address _preToken, uint256 _amount)
        internal
    {
        //the auction end is always set to now + the bid period
        pretokenContractAuctions[_preToken][_amount].auctionEnd =
            _getAuctionBidPeriod(_preToken, _amount) +
            uint64(block.timestamp);
        emit AuctionPeriodUpdated(
            _preToken,
            _amount,
            pretokenContractAuctions[_preToken][_amount].auctionEnd
        );
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       RESET FUNCTIONS        ║
      ╚══════════════════════════════╝*/

    /*
     * Reset all auction related parameters for Pretokens.
     * This effectively removes an EFT as an item up for auction
     */
    function _resetAuction(address _preToken, uint256 _amount)
        internal
    {
        pretokenContractAuctions[_preToken][_amount].minPrice = 0;
        pretokenContractAuctions[_preToken][_amount].buyNowPrice = 0;
        pretokenContractAuctions[_preToken][_amount].auctionEnd = 0;
        pretokenContractAuctions[_preToken][_amount].auctionBidPeriod = 0;
        pretokenContractAuctions[_preToken][_amount]
            .bidIncreasePercentage = 0;
        pretokenContractAuctions[_preToken][_amount].Seller = address(
            0
        );
        pretokenContractAuctions[_preToken][_amount]
            .whitelistedBuyer = address(0);
        pretokenContractAuctions[_preToken][_amount].ERC20Token = address(
            0
        );
    }

    /*
     * Reset all bid related parameters for an Pretoken.
     * This effectively sets an Pretoken as having no active bids
     */
    function _resetBids(address _preToken, uint256 _amount)
        internal
    {
        pretokenContractAuctions[_preToken][_amount]
            .HighestBidder = address(0);
        pretokenContractAuctions[_preToken][_amount].HighestBid = 0;
        pretokenContractAuctions[_preToken][_amount]
            .Recipient = address(0);
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       RESET FUNCTIONS        ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║         UPDATE BIDS          ║
      ╚══════════════════════════════╝*/
    /******************************************************************
     * Internal functions that update bid parameters and reverse bids *
     * to ensure contract only holds the highest bid.                 *
     ******************************************************************/
    function _updateHighestBid(
        address _preToken,
        uint256 _amount,
        uint128 _tokenAmount
    ) internal {
        address auctionERC20Token = pretokenContractAuctions[_preToken][
            _amount
        ].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            IERC20(auctionERC20Token).transferFrom(
                msg.sender,
                address(this),
                _tokenAmount
            );
            pretokenContractAuctions[_preToken][_amount]
                .HighestBid = _tokenAmount;
        } else {
            pretokenContractAuctions[_preToken][_amount]
                .HighestBid = uint128(msg.value);
        }
        pretokenContractAuctions[_preToken][_amount]
            .HighestBidder = msg.sender;
    }

    function _reverseAndResetPreviousBid(
        address _preToken,
        uint256 _amount
    ) internal {
        address HighestBidder = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBidder;

        uint128 HighestBid = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBid;
        _resetBids(_preToken, _amount);

        _payout(_preToken, _amount, HighestBidder, HighestBid);
    }

    function _reversePreviousBidAndUpdateHighestBid(
        address _preToken,
        uint256 _amount,
        uint128 _tokenAmount
    ) internal {
        address prevHighestBidder = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBidder;

        uint256 prevHighestBid = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBid;
        _updateHighestBid(_preToken, _amount, _tokenAmount);

        if (prevHighestBidder != address(0)) {
            _payout(
                _preToken,
                _amount,
                prevHighestBidder,
                prevHighestBid
            );
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║         UPDATE BIDS          ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║  TRANSFER PRETOKEN & PAY SELLER   ║
      ╚══════════════════════════════╝*/
    function _transferPretokenAndPaySeller(
        address _preToken,
        uint256 _amount
    ) internal {
        address _Seller = pretokenContractAuctions[_preToken][_amount]
            .Seller;
        address _HighestBidder = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBidder;
        address _Recipient = _getRecipient(_preToken, _amount);
        uint128 _HighestBid = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBid;
        _resetBids(_preToken, _amount);

        _payFeesAndSeller(
            _preToken,
            _amount,
            _Seller,
            _HighestBid
        );
        IERC20(_preToken).transferFrom(
            address(this),
            _Recipient,
            _amount
        );

        _resetAuction(_preToken, _amount);
        emit PretokenTransferredAndSellerPaid(
            _preToken,
            _amount,
            _Seller,
            _HighestBid,
            _HighestBidder,
            _Recipient
        );
    }

    function _payFeesAndSeller(
        address _preToken,
        uint256 _amount,
        address _Seller,
        uint256 _highestBid
    ) internal {
        uint256 feesPaid;
        for (
            uint256 i = 0;
            i <
            pretokenContractAuctions[_preToken][_amount]
                .feeRecipients
                .length;
            i++
        ) {
            uint256 fee = _getPortionOfBid(
                _highestBid,
                pretokenContractAuctions[_preToken][_amount]
                    .feePercentages[i]
            );
            feesPaid = feesPaid + fee;
            _payout(
                _preToken,
                _amount,
                pretokenContractAuctions[_preToken][_amount]
                    .feeRecipients[i],
                fee
            );
        }
        _payout(
            _preToken,
            _amount,
            _Seller,
            (_highestBid - feesPaid)
        );
    }

    function _payout(
        address _preToken,
        uint256 _amount,
        address _recipient,
        uint256 _amount
    ) internal {
        address auctionERC20Token = pretokenContractAuctions[_preToken][
            _amount
        ].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            IERC20(auctionERC20Token).transfer(_recipient, _amount);
        } else {
            // attempt to send the funds to the recipient
            (bool success, ) = payable(_recipient).call{
                value: _amount,
                gas: 20000
            }("");
            // if it failed, update their credit balance so they can pull it later
            if (!success) {
                failedTransferCredits[_recipient] =
                    failedTransferCredits[_recipient] +
                    _amount;
            }
        }
    }


    /*╔══════════════════════════════╗
      ║      SETTLE & WITHDRAW       ║
      ╚══════════════════════════════╝*/
    function settleAuction(address _preToken, uint256 _amount)
        external
        isAuctionOver(_preToken, _amount)
    {
        _transferPretokenAndPaySeller(_preToken, _amount);
        emit AuctionSettled(_preToken, _amount, msg.sender);
    }

    function withdrawAuction(address _preToken, uint256 _amount)
        external
    {
        //only the PRETOKEN owner can prematurely close and auction
        require(
            IERC20(_preToken).ownerOf(_amount) == msg.sender,
            "Not PRETOKEN owner"
        );
        _resetAuction(_preToken, _amount);
        emit AuctionWithdrawn(_preToken, _amount, msg.sender);
    }

    function withdrawBid(address _preToken, uint256 _amount)
        external
        minimumBidNotMade(_preToken, _amount)
    {
        address HighestBidder = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBidder;
        require(msg.sender == HighestBidder, "Cannot withdraw funds");

        uint128 HighestBid = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBid;
        _resetBids(_preToken, _amount);

        _payout(_preToken, _amount, HighestBidder, HighestBid);

        emit BidWithdrawn(_preToken, _amount, msg.sender);
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║      SETTLE & WITHDRAW       ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/
    function updateWhitelistedBuyer(
        address _preToken,
        uint256 _amount,
        address _newWhitelistedBuyer
    ) external onlySeller(_preToken, _amount) {
        require(_isASale(_preToken, _amount), "Not a sale");
        pretokenContractAuctions[_preToken][_amount]
            .whitelistedBuyer = _newWhitelistedBuyer;
        //if an underbid is by a non whitelisted buyer,reverse that bid
        address HighestBidder = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBidder;
        uint128 HighestBid = pretokenContractAuctions[_preToken][
            _amount
        ].HighestBid;
        if (HighestBid > 0 && !(HighestBidder == _newWhitelistedBuyer)) {
            //we only revert the underbid if the seller specifies a different
            //whitelisted buyer to the highest bider

            _resetBids(_preToken, _amount);

            _payout(
                _preToken,
                _amount,
                HighestBidder,
                HighestBid
            );
        }

        emit WhitelistedBuyerUpdated(
            _preToken,
            _amount,
            _newWhitelistedBuyer
        );
    }

    function updateMinimumPrice(
        address _preToken,
        uint256 _amount,
        uint128 _newMinPrice
    )
        external
        onlySeller(_preToken, _amount)
        minimumBidNotMade(_preToken, _amount)
        isNotASale(_preToken, _amount)
        priceGreaterThanZero(_newMinPrice)
        minPriceDoesNotExceedLimit(
            pretokenContractAuctions[_preToken][_amount].buyNowPrice,
            _newMinPrice
        )
    {
        pretokenContractAuctions[_preToken][_amount]
            .minPrice = _newMinPrice;

        emit MinimumPriceUpdated(_preToken, _amount, _newMinPrice);

        if (_isMinimumBidMade(_preToken, _amount)) {
            _transferPretokenToAuctionContract(_preToken, _amount);
            _updateAuctionEnd(_preToken, _amount);
        }
    }

    function updateBuyNowPrice(
        address _preToken,
        uint256 _amount,
        uint128 _newBuyNowPrice
    )
        external
        onlySeller(_preToken, _amount)
        priceGreaterThanZero(_newBuyNowPrice)
        minPriceDoesNotExceedLimit(
            _newBuyNowPrice,
            pretokenContractAuctions[_preToken][_amount].minPrice
        )
    {
        pretokenContractAuctions[_preToken][_amount]
            .buyNowPrice = _newBuyNowPrice;
        emit BuyNowPriceUpdated(_preToken, _amount, _newBuyNowPrice);
        if (_isBuyNowPriceMet(_preToken, _amount)) {
            _transferPretokenToAuctionContract(_preToken, _amount);
            _transferPretokenAndPaySeller(_preToken, _amount);
        }
    }

    /*
     * The Pretoken seller can opt to end an auction by taking the current highest bid.
     */
    function takeHighestBid(address _preToken, uint256 _amount)
        external
        onlySeller(_preToken, _amount)
    {
        require(
            _isABidMade(_preToken, _amount),
            "cannot payout 0 bid"
        );
        _transferPretokenToAuctionContract(_preToken, _amount);
        _transferPretokenAndPaySeller(_preToken, _amount);
        emit HighestBidTaken(_preToken, _amount);
    }

    /*
     * Query the owner of an Pretoken deposited for auction
     */
    function ownerOfPretoken(address _preToken, uint256 _amount)
        external
        view
        returns (address)
    {
        address Seller = pretokenContractAuctions[_preToken][_amount]
            .Seller;
        require(Seller != address(0), "Pretoken not deposited");

        return Seller;
    }

    /*
     * If the transfer of a bid has failed, allow the recipient to reclaim their amount later.
     */
    function withdrawAllFailedCredits() external {
        uint256 amount = failedTransferCredits[msg.sender];

        require(amount != 0, "no credits to withdraw");

        failedTransferCredits[msg.sender] = 0;

        (bool successfulWithdraw, ) = msg.sender.call{
            value: amount,
            gas: 20000
        }("");
        require(successfulWithdraw, "withdraw failed");
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/
    /**********************************/
}