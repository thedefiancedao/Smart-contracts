// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/ISwap.sol";
import "../interfaces/IDefiantBridge.sol";
import "../interfaces/IWETH9.sol";

interface IFrax {
    function exchangeCanonicalForOld(address bridge_token_address, uint256 token_amount) external returns (uint256);
}

contract MoonriverBridgeZap {
    using SafeERC20 for IERC20;

    IDefiantBridge defiantBridge;
    address payable public immutable WETH_ADDRESS;
    IFrax private  constant CANOLICAL_FRAX = IFrax(0x1A93B23281CC1CDE4C4741353F3064709A16197d);
    IERC20 private constant DEF_FRAX = IERC20(0xE96AC70907ffF3Efee79f502C985A7A21Bce407d);

    mapping(address => address) public swapMap;
    mapping(address => IERC20[]) public swapTokensMap;

    uint256 constant MAX_UINT256 = 2**256 - 1;

    constructor(
        address payable _wethAddress,
        address _swapOne,
        address tokenOne,
        address _swapTwo,
        address tokenTwo,
        IDefiantBridge _defiantBridge
    ) public {
        WETH_ADDRESS = _wethAddress;
        defiantBridge = _defiantBridge;
        swapMap[tokenOne] = _swapOne;
        swapMap[tokenTwo] = _swapTwo;
        IERC20(_wethAddress).safeIncreaseAllowance(address(_defiantBridge), MAX_UINT256);
        if (address(_swapOne) != address(0)) {
            {
                uint8 i;
                for (; i < 32; i++) {
                    try ISwap(_swapOne).getToken(i) returns (
                        IERC20 token
                    ) {
                        swapTokensMap[_swapOne].push(token);
                        token.safeApprove(address(_swapOne), MAX_UINT256);
                        token.safeApprove(address(defiantBridge), MAX_UINT256);
                    } catch {
                        break;
                    }
                }
                require(i > 1, "swap must have at least 2 tokens");
            }
        }
        if (address(_swapTwo) != address(0)) {
            {
                uint8 i;
                for (; i < 32; i++) {
                    try ISwap(_swapTwo).getToken(i) returns (
                        IERC20 token
                    ) {
                        swapTokensMap[_swapTwo].push(token);
                        token.safeApprove(address(_swapTwo), MAX_UINT256);
                        token.safeApprove(address(defiantBridge), MAX_UINT256);
                    } catch {
                        break;
                    }
                }
                require(i > 1, "swap must have at least 2 tokens");
            }
        }
    }

    /**
     * @notice Calculate amount of tokens you receive on swap
     * @param tokenIndexFrom the token the user wants to sell
     * @param tokenIndexTo the token the user wants to buy
     * @param dx the amount of tokens the user wants to sell. If the token charges
     * a fee on transfers, use the amount that gets transferred after the fee.
     * @return amount of tokens the user will receive
     */
    function calculateSwap(
        IERC20 token,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx
    ) external view virtual returns (uint256) {
        ISwap swap = ISwap(
            swapMap[address(token)]
        );
        return swap.calculateSwap(tokenIndexFrom, tokenIndexTo, dx);
    }

    function swapAndRedeem(
        address to,
        uint256 chainId,
        IERC20 token,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external {
        ISwap swap = ISwap(swapMap[address(token)]);
        require(address(swap) != address(0), "Swap is 0x00");
        IERC20[] memory tokens = swapTokensMap[address(swap)];
        tokens[tokenIndexFrom].safeTransferFrom(
            msg.sender,
            address(this),
            dx
        );
        // swap

        uint256 swappedAmount = swap.swap(
            tokenIndexFrom,
            tokenIndexTo,
            dx,
            minDy,
            deadline
        );
        // deposit into bridge, gets nUSD
        if (
            token.allowance(address(this), address(defiantBridge)) <
            swappedAmount
        ) {
            token.safeApprove(address(defiantBridge), MAX_UINT256);
        }
        defiantBridge.redeem(to, chainId, token, swappedAmount);
    }

    function swapAndRedeemAndSwap(
        address to,
        uint256 chainId,
        IERC20 token,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline,
        uint8 swapTokenIndexFrom,
        uint8 swapTokenIndexTo,
        uint256 swapMinDy,
        uint256 swapDeadline
    ) external {
        require(
            address(swapMap[address(token)]) != address(0),
            "Swap is 0x00"
        );
        IERC20[] memory tokens = swapTokensMap[
            swapMap[address(token)]
        ];
        tokens[tokenIndexFrom].safeTransferFrom(
            msg.sender,
            address(this),
            dx
        );
        // swap

        uint256 swappedAmount = ISwap(swapMap[address(token)]).swap(tokenIndexFrom, tokenIndexTo, dx, minDy, deadline);
        // deposit into bridge, gets nUSD
        if (
            token.allowance(address(this), address(defiantBridge)) <
            swappedAmount
        ) {
            token.safeApprove(address(defiantBridge), MAX_UINT256);
        }
        defiantBridge.redeemAndSwap(
            to,
            chainId,
            token,
            swappedAmount,
            swapTokenIndexFrom,
            swapTokenIndexTo,
            swapMinDy,
            swapDeadline
        );
    }

    function swapAndRedeemAndRemove(
        address to,
        uint256 chainId,
        IERC20 token,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline,
        uint8 liqTokenIndex,
        uint256 liqMinAmount,
        uint256 liqDeadline
    ) external {
        ISwap swap = ISwap(swapMap[address(token)]);
        require(address(swap) != address(0), "Swap is 0x00");
        IERC20[] memory tokens = swapTokensMap[address(swap)];
        tokens[tokenIndexFrom].safeTransferFrom(
            msg.sender,
            address(this),
            dx
        );
        // swap

        uint256 swappedAmount = swap.swap(
            tokenIndexFrom,
            tokenIndexTo,
            dx,
            minDy,
            deadline
        );
        // deposit into bridge, gets nUSD
        if (
            token.allowance(address(this), address(defiantBridge)) <
            swappedAmount
        ) {
            token.safeApprove(address(defiantBridge), MAX_UINT256);
        }
        defiantBridge.redeemAndRemove(
            to,
            chainId,
            token,
            swappedAmount,
            liqTokenIndex,
            liqMinAmount,
            liqDeadline
        );
    }

    /**
     * @notice wraps defiantBridge redeem()
     * @param to address on other chain to redeem underlying assets to
     * @param chainId which underlying chain to bridge assets onto
     * @param token ERC20 compatible token to deposit into the bridge
     * @param amount Amount in native token decimals to transfer cross-chain pre-fees
     **/
    function redeem(
        address to,
        uint256 chainId,
        IERC20 token,
        uint256 amount
    ) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (address(token) == address(CANOLICAL_FRAX)) {
            uint256 swappedAmount = CANOLICAL_FRAX.exchangeCanonicalForOld(address(DEF_FRAX), amount);
            if (def_FRAX.allowance(address(this), address(defiantBridge)) < amount) {
                DEF_FRAX.safeApprove(address(defiantBridge), MAX_UINT256);
            }
            defiantBridge.redeem(to, chainId, DEF_FRAX, swappedAmount);
        } else {
            if (token.allowance(address(this), address(defiantBridge)) < amount) {
                token.safeApprove(address(defiantBridge), MAX_UINT256);
            }
            defiantBridge.redeem(to, chainId, token, amount);
        }
    }

    /**
 * @notice Wraps defiantBridge redeemv2() function
   * @param to address on other chain to bridge assets to
   * @param chainId which chain to bridge assets onto
   * @param token ERC20 compatible token to redeem into the bridge
   * @param amount Amount in native token decimals to transfer cross-chain pre-fees
   **/
    function redeemv2(
        bytes32 to,
        uint256 chainId,
        IERC20 token,
        uint256 amount
    ) external {
        token.safeTransferFrom(msg.sender, address(this), amount);

        if (token.allowance(address(this), address(defiantBridge)) < amount) {
            token.safeApprove(address(defiantBridge), MAX_UINT256);
        }
        defiantBridge.redeemv2(to, chainId, token, amount);
    }

    /**
     * @notice wraps defiantBridge redeem()
     * @param to address on other chain to redeem underlying assets to
     * @param chainId which underlying chain to bridge assets onto
     * @param token ERC20 compatible token to deposit into the bridge
     * @param amount Amount in native token decimals to transfer cross-chain pre-fees
     **/
    function deposit(
        address to,
        uint256 chainId,
        IERC20 token,
        uint256 amount
    ) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (token.allowance(address(this), address(defiantBridge)) < amount) {
            token.safeApprove(address(defiantBridge), MAX_UINT256);
        }
        defiantBridge.deposit(to, chainId, token, amount);
    }

    /**
   * @notice Wraps defiantBridge deposit() function to make it compatible w/ ETH -> WETH conversions
   * @param to address on other chain to bridge assets to
   * @param chainId which chain to bridge assets onto
   * @param amount Amount in native token decimals to transfer cross-chain pre-fees
   **/
  function depositETH(
    address to,
    uint256 chainId,
    uint256 amount
    ) external payable {
      require(msg.value > 0 && msg.value == amount, 'INCORRECT MSG VALUE');
      IWETH9(WETH_ADDRESS).deposit{value: msg.value}();
      defiantBridge.deposit(to, chainId, IERC20(WETH_ADDRESS), amount);
    }



    function swapETHAndRedeem(
        address to,
        uint256 chainId,
        IERC20 token,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external payable {
        require(WETH_ADDRESS != address(0), "WETH 0");
        require(msg.value > 0 && msg.value == dx, "INCORRECT MSG VALUE");
        ISwap swap = ISwap(swapMap[address(token)]);
        require(address(swap) != address(0), "Swap is 0x00");
        IWETH9(WETH_ADDRESS).deposit{value: msg.value}();

        // swap
        uint256 swappedAmount = swap.swap(
            tokenIndexFrom,
            tokenIndexTo,
            dx,
            minDy,
            deadline
        );
        defiantBridge.redeem(to, chainId, token, swappedAmount);
    }

    /**
     * @notice Wraps redeemAndSwap on defiantBridge.sol
     * Relays to nodes that (typically) a wrapped defAsset ERC20 token has been burned and the underlying needs to be redeeemed on the native chain. This function indicates to the nodes that they should attempt to redeem the LP token for the underlying assets (E.g "swap" out of the LP token)
     * @param to address on other chain to redeem underlying assets to
     * @param chainId which underlying chain to bridge assets onto
     * @param token ERC20 compatible token to deposit into the bridge
     * @param amount Amount in native token decimals to transfer cross-chain pre-fees
     * @param tokenIndexFrom the token the user wants to swap from
     * @param tokenIndexTo the token the user wants to swap to
     * @param minDy the min amount the user would like to receive, or revert to only minting the DefERC20 token crosschain.
     * @param deadline latest timestamp to accept this transaction
     **/
    function redeemAndSwap(
        address to,
        uint256 chainId,
        IERC20 token,
        uint256 amount,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 minDy,
        uint256 deadline
    ) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (token.allowance(address(this), address(defiantBridge)) < amount) {
            token.safeApprove(address(defiantBridge), MAX_UINT256);
        }
        defiantBridge.redeemAndSwap(
            to,
            chainId,
            token,
            amount,
            tokenIndexFrom,
            tokenIndexTo,
            minDy,
            deadline
        );
    }

    /**
     * @notice Wraps redeemAndRemove on defiantBridge
     * Relays to nodes that (typically) a wrapped defAsset ERC20 token has been burned and the underlying needs to be redeeemed on the native chain. This function indicates to the nodes that they should attempt to redeem the LP token for the underlying assets (E.g "swap" out of the LP token)
     * @param to address on other chain to redeem underlying assets to
     * @param chainId which underlying chain to bridge assets onto
     * @param token ERC20 compatible token to deposit into the bridge
     * @param amount Amount of (typically) LP token to pass to the nodes to attempt to removeLiquidity() with to redeem for the underlying assets of the LP token
     * @param liqTokenIndex Specifies which of the underlying LP assets the nodes should attempt to redeem for
     * @param liqMinAmount Specifies the minimum amount of the underlying asset needed for the nodes to execute the redeem/swap
     * @param liqDeadline Specificies the deadline that the nodes are allowed to try to redeem/swap the LP token
     **/
    function redeemAndRemove(
        address to,
        uint256 chainId,
        IERC20 token,
        uint256 amount,
        uint8 liqTokenIndex,
        uint256 liqMinAmount,
        uint256 liqDeadline
    ) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (token.allowance(address(this), address(defiantBridge)) < amount) {
            token.safeApprove(address(defiantBridge), MAX_UINT256);
        }
        defiantBridge.redeemAndRemove(
            to,
            chainId,
            token,
            amount,
            liqTokenIndex,
            liqMinAmount,
            liqDeadline
        );
    }
}
