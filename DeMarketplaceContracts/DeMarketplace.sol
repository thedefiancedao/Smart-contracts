// SPDX-License-Identifier: MIT
pragma solidity >=0.4.21 <0.8.0;

// import ERC721 iterface
import "./ERC20.sol";

library SafeERC20{
    using Address for address;

    function safeTransfer  (
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface IDeMarketplaceHolder {
	function _buy (address token, address to, uint256 amount) external payable;
}

contract DeMarketplaeHolder is IDeMarketplaceHolder{

	address fundContract;

	constructor (address _fundContract) {
        fundContract = _fundContract;
    }

	function _buy (address token, address to, uint256 amount) override external payable {
        require(msg.sender == fundContract, "Illegal request");
		IERC20(token).transfer(to, amount);
	}
}

// CryptoBoys smart contract inherits ERC721 interface
contract DeMarketplace is ERC20 {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    address private creator;
    
    DeMarketplaceHolder public holder;

    address public USDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    struct itemInfo {
        address tokenAddress;                   // Project Token Contract Address
        string tokenSymbol;                     // Project Token Symbol
        address payable USDCWallet;             // Seller's wallet where USDC will be sent to
        uint256 tokenAmount;                    // Total amount to be raised
        uint256 currentAmount;                    // Current amount
        uint16 tokenPrice;                    // Token price
        address ownerAddress;
    }

    itemInfo[] public items;              // Array of Item Information

    // initialize contract while deployment with contract's collection name and token
    function register(
        string memory tokenSymbol,              // Project Token Symbol
        address tokenAddress,                   // Project Token Contract Address
        address payable USDCWallet,             // User wallet where USDC will be sent to
        uint256 tokenAmount,                    // Total amount to be raised
        uint16 tokenPrice                      // USCD amount for a token
    ) external payable {
        
        itemInfo memory newItem = itemInfo(
            {
                tokenSymbol: tokenSymbol,
                tokenAddress: tokenAddress,
                USDCWallet: USDCWallet,
                tokenAmount: tokenAmount,
                tokenPrice: tokenPrice,
                currentAmount: tokenAmount,
                ownerAddress: msg.sender
            }
        );

        items.push(newItem);
        IERC20(tokenAddress).transferFrom(msg.sender, address(holder), tokenAmount);
    }

  // get owner of the token
  function getTokenOwner(uint256 _tokenId) public view returns(address) {
    address _tokenOwner = ownerOf(_tokenId);
    return _tokenOwner;
  }

  // get metadata of the token
  function getTokenMetaData(uint _tokenId) public view returns(string memory) {
    string memory tokenMetaData = tokenURI(_tokenId);
    return tokenMetaData;
  }

  function getNumberOfTokens() public view returns(uint256) {
    uint256 totalNumberOfTokensMinted = totalSupply();
    return totalNumberOfTokensMinted;
  }

  // get total number of tokens owned by an address
  function getTotalNumberOfTokensOwnedByAnAddress(address _owner) public view returns(uint256) {
    uint256 totalNumberOfTokensOwned = balanceOf(_owner);
    return totalNumberOfTokensOwned;
  }

  // check if the token already exists
  function getTokenExists(uint256 _tokenId) public view returns(bool) {
    bool tokenExists = _exists(_tokenId);
    return tokenExists;
  }

  function buyToken(uint256 _itemId, uint256 amount) public payable {
    // check if the function caller is not an zero account address
    require(msg.sender != address(0));

    require(_exists(_itemId));

    // get the token's owner
    address tokenOwner = itemInfo[_itemId].ownerAddress;
    // token's owner should not be an zero address account
    require(ownerAddress != address(0));
    // the one who wants to buy the token should not be the token's owner
    require(ownerAddress != msg.sender);
    // get that token from all crypto boys mapping and create a memory of it defined as (struct => CryptoBoy)
    itemInfo memory currentItem = items[_itemId];
    // price sent in to buy should be equal to or more than the token's price
    require(msg.value >= currentItem.tokenPrice * amount);
    // transfer the token from owner to the caller of the function (buyer)
    IERC20(currentItem.tokenAddress).transferFrom(address(holder), msg.sender, amount);
    // get owner of the token
    IERC20(USDCAddress).transferFrom(address(this), currentItem.USDCWallet, msg.value);

    currentItem.currentAmount = currentItem.currentAmount - amount;
  }

  function changeTokenPrice(uint256 _itemId, uint256 _newPrice) public {
    // require caller of the function is not an empty address
    require(msg.sender != address(0));
    // require that token should exist
    require(_exists(_itemId));
    // get the token's owner
    address tokenOwner = items[_itemId].ownerAddress;
    // token's owner should not be an zero address account
    require(ownerAddress != address(0));

    itemInfo memory currentItem = items[_itemId];
    // update token's price with new price
    currentItem.tokenPrice = _newPrice;
    // set and update that token in the mapping
    items[_itemId] = currentItem;
  }
}