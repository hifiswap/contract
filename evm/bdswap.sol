// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IUniswapV2Pool {
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniswapV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256, int256);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IWrappedToken {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

library SafeERC20 {
    
    error SafeERC20FailedOperation(address token);

    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function trySafeTransfer(IERC20 token, address to, uint256 value) internal returns (bool) {
        return _safeTransfer(token, to, value, false);
    }

    function trySafeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        return _safeTransferFrom(token, from, to, value, false);
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true)) revert SafeERC20FailedOperation(address(token));
            if (!_safeApprove(token, spender, value, true)) revert SafeERC20FailedOperation(address(token));
        }
    }

    function _safeTransfer(IERC20 token, address to, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = IERC20.transfer.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(to, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
            if iszero(and(success, eq(mload(0x00), 1))) {
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
        }
    }

    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value,
        bool bubble
    ) private returns (bool success) {
        bytes4 selector = IERC20.transferFrom.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(from, shr(96, not(0))))
            mstore(0x24, and(to, shr(96, not(0))))
            mstore(0x44, value)
            success := call(gas(), token, 0, 0x00, 0x64, 0x00, 0x20)
            if iszero(and(success, eq(mload(0x00), 1))) {
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
            mstore(0x60, 0)
        }
    }

    function _safeApprove(IERC20 token, address spender, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = IERC20.approve.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(spender, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
            if iszero(and(success, eq(mload(0x00), 1))) {
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
        }
    }
}

contract Hifiswap {

    using SafeERC20 for IERC20;

    mapping(address => bool) public owners;
    address public immutable TOKEN_WRAPPER;
    uint8 internal constant HEADER_LENGTH = 54;  
    uint8 internal constant PARAMS_LENGTH = 100; 
    bytes32 private constant POOL_TOKEN_SLOT = keccak256("hifiswap.pool.token.slot");
    bytes32 private constant POOL_AMOUNT_SLOT = keccak256("hifiswap.pool.amount.slot");
    bytes32 private constant POOL_ADDRESS_SLOT = keccak256("hifiswap.pool.address.slot");
    uint160 internal constant MINIMUM_SQRT_PRICE_LIMIT = 4295128739;
    uint160 internal constant MAXIMUM_SQRT_PRICE_LIMIT = 1461446703485210103287273052203988822378723970342;

    event OnWrap(uint256 amount);
    event OnUnwrap(uint256 amount);
    event OnOwner(address indexed owner, bool status);
    event OnWithdraw(address indexed token, address indexed receiver, uint256 amount);

    modifier onlyOwner() { require(owners[msg.sender], "#1"); _; }

    constructor(address tokenWrapper) {
        require(tokenWrapper != address(0), "zero wrapper");
        TOKEN_WRAPPER = tokenWrapper;
        owners[msg.sender] = true;
    }

    receive() external payable {}

    // 代币交换
    fallback() external payable onlyOwner {
        require(msg.data.length >= PARAMS_LENGTH + 4, "#2");
        swap(msg.data.length - 4);
    }

    // 执行交换
    function swap(uint256 length) private {

        address signer = msg.sender;
        address receiver = readAddress(0);
        address outputToken = readAddress(20);
        uint256 inputAmount = readAmount(40);
        uint256 outputMinimum = readAmount(45);
        uint256 maxBlock = readUint32(50);                          

        require(maxBlock == 0 || block.number <= maxBlock, "#30");
        require(inputAmount > 0, "#3");
        require(outputMinimum > 0, "#4");
        require(receiver != address(0), "#5");

        address inputToken = loadFunder(signer, inputAmount);
        address realOutputToken = (outputToken == address(0))? TOKEN_WRAPPER: outputToken;
        uint256 balanceBefore = IERC20(realOutputToken).balanceOf(address(this));

        uint256 offset = HEADER_LENGTH;
        uint256 layerCount = readUint8(offset); offset += 1;
        for (uint256 layerIndex = 0; layerIndex < layerCount;) {
            uint256 swapCount = readUint8(offset); offset += 1;
            address layerInputToken = readAddress(offset); offset += 20;
            uint256 layerInputAmount = (layerInputToken == inputToken) ? inputAmount : 0;
            for (uint256 swapIndex = 0; swapIndex < swapCount;) {
                offset = executeSwap(offset, layerInputAmount, layerInputToken, length);
                unchecked { ++swapIndex; }
            }
            unchecked { ++layerIndex; }
        }

        uint256 outputAmount = IERC20(realOutputToken).balanceOf(address(this)) - balanceBefore;
        require(outputAmount >= outputMinimum, "#8");
        sendToAddress(outputToken, receiver, outputAmount);
    }

    // 执行交换
    function executeSwap(uint256 offset, uint256 layerInputAmount, address layerInputToken, uint256 length) internal returns (uint256) {

        uint8 pairVersion = readUint8 (offset); offset += 1;
        uint8 swapFlags = readUint8 (offset); offset += 1;
        uint16 swapRatio = readUint16(offset); offset += 2;
        bool zeroForOne = (swapFlags & 0x01) != 0;
        require(swapRatio <= 10000, "#12");
        uint256 swapInputAmount = 0;
        if (swapRatio == 0) {
            swapInputAmount = IERC20(layerInputToken).balanceOf(address(this));
        } else {
            if (layerInputAmount == 0) {
                layerInputAmount = IERC20(layerInputToken).balanceOf(address(this));
            }
            swapInputAmount = (layerInputAmount * uint256(swapRatio)) / 10000;
        }
        require(swapInputAmount > 0, "#13");
        if (pairVersion == 1) {
            require(offset + 22 <= length, "#14");
            address poolAddress = readAddress(offset); offset += 20;
            uint16  swapFee = readUint16 (offset); offset += 2;
            executeUniswapV2(poolAddress, layerInputToken, swapInputAmount, swapFee, zeroForOne);
        } else if (pairVersion == 2 || pairVersion == 3) {
            require(offset + 20 <= length, "#15");
            address poolAddress = readAddress(offset); offset += 20;
            executeUniswapV3(poolAddress, layerInputToken, swapInputAmount, zeroForOne);
        } else {
            revert("#16");
        }

        return offset;
    }

    // 执行UniswapV2
    function executeUniswapV2(address poolAddress,address inputToken,uint256 inputAmount,uint16 swapFee,bool zeroForOne) private {
        IERC20(inputToken).safeTransfer(poolAddress, inputAmount);
        uint256 swapOutputAmount = quoteUniswapV2(poolAddress, inputAmount, swapFee, zeroForOne);
        require(swapOutputAmount > 0, "#17");
        IUniswapV2Pool(poolAddress).swap(zeroForOne ? 0 : swapOutputAmount,zeroForOne ? swapOutputAmount : 0,address(this),"");
    }

    // 执行UniswapV3
    function executeUniswapV3(address poolAddress, address inputToken, uint256 inputAmount, bool zeroForOne) private {
        require(inputAmount <= uint256(type(int256).max), "#18");
        bytes32 tokenSlot = POOL_TOKEN_SLOT;
        bytes32 amountSlot = POOL_AMOUNT_SLOT;
        bytes32 poolSlot = POOL_ADDRESS_SLOT;
        assembly { tstore(poolSlot, poolAddress) tstore(tokenSlot, inputToken) tstore(amountSlot, inputAmount) }
        IUniswapV3Pool(poolAddress).swap(address(this),zeroForOne,int256(inputAmount),zeroForOne ? MINIMUM_SQRT_PRICE_LIMIT + 1 : MAXIMUM_SQRT_PRICE_LIMIT - 1,"");
    }

    // 输出UniswapV2
    function quoteUniswapV2(address poolAddress, uint256 inputAmount, uint16 swapFee, bool zeroForOne) internal view returns (uint256) {
        require(swapFee < 1_000_000, "#19");
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pool(poolAddress).getReserves();
        (uint256 reserveInput, uint256 reserveOutput) = zeroForOne? (reserve0, reserve1): (reserve1, reserve0);
        uint256 feeMultiplier = 1_000_000 - uint256(swapFee);
        return (inputAmount * feeMultiplier * reserveOutput) / (reserveInput * 1_000_000 + inputAmount * feeMultiplier);
    }

    // 回调UniswapV3
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata callbackData) external {
        doUniswapV3Callback(amount0Delta, amount1Delta, callbackData);
    }

    // 回调PancakeV3
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata callbackData) external {
        doUniswapV3Callback(amount0Delta, amount1Delta, callbackData);
    }

    // 处理回调
    function doUniswapV3Callback(int256 amount0Delta, int256 amount1Delta, bytes calldata) private {
        uint256 maxOutput;
        address inputToken;
        address poolAddress;
        bytes32 tokenSlot = POOL_TOKEN_SLOT;
        bytes32 poolSlot = POOL_ADDRESS_SLOT;
        bytes32 amountSlot = POOL_AMOUNT_SLOT;
        assembly {
            poolAddress := tload(poolSlot)
            inputToken := tload(tokenSlot)
            maxOutput := tload(amountSlot)
        }
        require(msg.sender == poolAddress, "#20");
        assembly { tstore(poolSlot, 0) tstore(tokenSlot, 0) tstore(amountSlot, 0) }
        uint256 amountOutput;
        if (amount0Delta > 0) {
            amountOutput = uint256(amount0Delta);
        } else if (amount1Delta > 0)  {
            amountOutput = uint256(amount1Delta);
        }else  {
            revert("#21");
        }
        require(amountOutput <= maxOutput, "#22");
        IERC20(inputToken).safeTransfer(msg.sender, amountOutput);
    }

    // 加载资金
    function loadFunder(address signer, uint256 inputAmount) private returns (address) {
        address inputToken = readAddress(HEADER_LENGTH + 2);
        if (msg.value > 0) {
            require(msg.value == inputAmount, "#9");
            require(inputToken == TOKEN_WRAPPER, "#10");
            IWrappedToken(TOKEN_WRAPPER).deposit{value: inputAmount}();
            return TOKEN_WRAPPER;
        } else {
            IERC20(inputToken).safeTransferFrom(signer, address(this), inputAmount);
            return inputToken;
        }
    }

    // 发送资金
    function sendToAddress(address outputToken, address receiver, uint256 outputAmount) private {
        if (outputToken == address(0)) {
            IWrappedToken(TOKEN_WRAPPER).withdraw(outputAmount);
            (bool success,) = payable(receiver).call{value: outputAmount}("");
            require(success, "#11");
        } else {
            IERC20(outputToken).safeTransfer(receiver, outputAmount);
        }
    }

    // 设置管理员
    function setOwner(address[] calldata addresses, bool status) external onlyOwner {
        for (uint256 i = 0; i < addresses.length;) {
            require(addresses[i] != address(0), "#23");
            owners[addresses[i]] = status;
            emit OnOwner(addresses[i], status);
            unchecked { ++i; }
        }
        require(owners[msg.sender], "#24");
    }

    // 管理员提取资金
    function withdraw(address token) external onlyOwner {
        address receiver = msg.sender;
        uint256 amount;
        if (token == address(0)) {
            amount = address(this).balance;
            (bool success,) = payable(receiver).call{value: amount}("");
            require(success, "#25");
        } else {
            amount = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(receiver, amount);
        }
        emit OnWithdraw(token, receiver, amount);
    }

    // 打包原生币
    function wrap() external payable onlyOwner {
        uint256 amount = msg.value;
        require(amount > 0, "#26");
        IWrappedToken(TOKEN_WRAPPER).deposit{value: amount}();
        IERC20(TOKEN_WRAPPER).safeTransfer(msg.sender, amount);
        emit OnWrap(amount);
    }

    // 解包原生币
    function unwrap(uint256 amount) external onlyOwner {
        require(amount > 0, "#27");
        IERC20(TOKEN_WRAPPER).safeTransferFrom(msg.sender, address(this), amount);
        IWrappedToken(TOKEN_WRAPPER).withdraw(amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "#28");
        emit OnUnwrap(amount);
    }

    function readAmount(uint256 offset) internal pure returns (uint256) {
        uint32 number = readUint32(offset);
        uint8  shift  = readUint8 (offset + 4);
        uint256 result = uint256(number) << uint256(shift);
        require(result >> uint256(shift) == uint256(number), "#29");
        return result;
    }

    function readAddress(uint256 offset) internal pure returns (address result) {
        assembly { result := shr(96, calldataload(add(4, offset))) }
    }

    function readUint8(uint256 offset) internal pure returns (uint8 result) {
        assembly { result := byte(0, calldataload(add(4, offset))) }
    }

    function readUint16(uint256 offset) internal pure returns (uint16 result) {
        assembly { result := shr(240, calldataload(add(4, offset))) }
    }

    function readUint32(uint256 offset) internal pure returns (uint32 result) {
        assembly { result := shr(224, calldataload(add(4, offset))) }
    }

}
