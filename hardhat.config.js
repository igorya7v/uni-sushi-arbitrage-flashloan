/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 
require("@nomiclabs/hardhat-waffle");
 
module.exports = {
	
	solidity: {
		compilers: [
			{
				version: "0.7.3"
			},
			{
				version: "0.6.6"
			}
		]
	}
};
