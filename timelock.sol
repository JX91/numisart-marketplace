// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.4;

import "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimeLock is TimelockController {

    //Run timelock contract before target contract
    //Set all value before timelock implemented
    // minDelay: How long you have to wait before executing
    // proposers is the list of the addresses that can propose
    // executors: Who can execute when a proposal passes

    /* minDelay:172800 , proposers:dev address in array, executors:dev address in array */
    constructor(
        uint256 minDelay,   
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors) {}
    
    /*1. Run schedule function*/
    /*target: target contract address*/
    /*value: 0*/
    /*data: calldata of the contract funtion that wanted to set as timelock (from backend)*/
    /*predecessor: 0x0000000000000000000000000000000000000000000000000000000000000000*/
    /*salt: 0x0000000000000000000000000000000000000000000000000000000000000000*/
    /*delay: duration of delay in second*/

    /*Set gov address to timelock contract address*/
    /*2. Run execute function (after scheduled time passed)*/
    /*payableAmount: 0*/
    /*target: target contract address*/
    /*value: 0*/
    /*data: calldata of the contract funtion that wanted to set as timelock (from backend)*/
    /*predecessor: 0x0000000000000000000000000000000000000000000000000000000000000000*/
    /*salt: 0x0000000000000000000000000000000000000000000000000000000000000000*/
}