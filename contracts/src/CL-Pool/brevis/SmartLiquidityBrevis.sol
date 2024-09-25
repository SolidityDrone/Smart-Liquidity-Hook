// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./BrevisAppZkOnly.sol";


contract SmartLiquidityBrevis is BrevisAppZkOnly, Ownable {

    bytes32 public vkHash;

    constructor(address _brevisRequest) BrevisAppZkOnly(_brevisRequest) Ownable(msg.sender) {}


    function handleProofResult(
        bytes32 _vkHash,
        bytes calldata _circuitOutput
    ) internal override(BrevisAppZkOnly) {
      
        require(vkHash == _vkHash, "invalid vk");
       
     
    }

    function decodeOutput(bytes calldata o) internal pure returns (bytes32, uint256, uint64, address) {
        // this variable is not used, it's only here because we wanted to show an example of outputting bytes32
        bytes32 salt = bytes32(o[0:32]);

        uint256 sumVolume;
        uint64 minBlockNum;
        address addr;
        return (salt, sumVolume, minBlockNum, addr);
    }
 
    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }
}