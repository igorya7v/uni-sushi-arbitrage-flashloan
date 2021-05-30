// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IERC20.sol';

contract ArbitrageBot {
	
	// Uniswap Factory
	address public uFactory;
	// Sushiswap Router 
	//(Sushiswap is a fork of Uniswap, therefore the same interface)
	IUniswapV2Router02 public sRouter;
	
	// Unix timestamp after which the transaction will revert.
	uint deadline;
	address operator;
	

	constructor(address _uFactory, address _sRouter) public {
		uFactory = _uFactory;
		sRouter = IUniswapV2Router02(_sRouter);
	}
	
	// The entry point to start the arbitrage flow.
	// The outside logic we call that function,
	// whenever there is an opportunity for arbitrage trade
	// between the Uniswap and Sushiswap platforms.
	// 
	// @param amount0/amount1	Determines which token to borrow from the Uniswap flash loan.
	function doArbitrage(
		address token0, 
		address token1, 
		uint amount0, 
		uint amount1,
		uint _deadline
	) 
		external 
	{
		address pairAddress = IUniswapV2Factory(uFactory).getPair(token0, token1);
		require(pairAddress != address(0), 'This pool does not exist');
		
		operator = msg.sender;
		deadline = _deadline;
		
		// For the Uniswap flash loan we need to call the low level function.
		// The amount that is not zero we be borrowed in the flash loan.
		// The borrowed tokens will be transfered to 'address(this)'.
		// the 'bytes('not empty')' param triggers the flash loan, 
		// otherwise a normal swap will be executed.
		// On successfull loan execution the 'uniswapV2Call' function
		// will be called from the Uniswap pair contract.
		IUniswapV2Pair(pairAddress).swap(
			amount0, 
			amount1, 
			address(this), 
			bytes('not empty')
		);
	}
	
	// This function will be called from the UniswapPair contract
	// after the succesfull execution of flash loan.
	//
	// @sender			The address of the flash loan initiator (the ArbitrageBot).
	// @amount0/amount1	The actual amount of the borrowed tokens.
	// @data			bytes('not empty')
	function uniswapV2Call(
		address _sender, 
		uint _amount0, 
		uint _amount1, 
		bytes calldata _data
	) 
		external 
	{
		address[] memory path = new address[](2);
		uint amountToken = _amount0 == 0 ? _amount1 : _amount0;
		
		// msg.sender is the UniswapPair contract
		address token0 = IUniswapV2Pair(msg.sender).token0();
		address token1 = IUniswapV2Pair(msg.sender).token1();
		
		// Validate that the call is coming from the correct UniswapPair contract.
		require(
			msg.sender == UniswapV2Library.pairFor(uFactory, token0, token1), 
			'Unauthorized'
		);
		
		require(_amount0 == 0 || _amount1 == 0);

		path[0] = _amount0 == 0 ? token1 : token0;
		path[1] = _amount0 == 0 ? token0 : token1;
		
		// Ponter to a token to sell on Sushiswap.
		IERC20 token = IERC20(_amount0 == 0 ? token1 : token0);
		
		// Approve Sushiswap to transform the tokens.
		token.approve(address(sRouter), amountToken);
		
		// Get how many tokens we need to return to the Uniswap flashloan.
		// Amount required to preserve the pair reserve before the flashloan plus 0.3% LP fee
		uint amountRequired = UniswapV2Library.getAmountsIn(
			uFactory, 
			amountToken, 
			path
		)[0];
		
		// Sell the borrowed tokens on Sushiswap
		// amountRequired is the minimum out amount of swap tokens 
		uint amountReceived = sRouter.swapExactTokensForTokens(
			amountToken, 
			amountRequired, 
			path, 
			address(this), 
			deadline
		)[1];

		IERC20 otherToken = IERC20(_amount0 == 0 ? token0 : token1);
		// Repay the flashloan back.
		otherToken.transfer(msg.sender, amountRequired);
		// Transfer the rest to the operator.
		otherToken.transfer(operator, amountReceived - amountRequired);
	}
}