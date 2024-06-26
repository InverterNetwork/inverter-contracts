// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";
import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

interface IModuleImplementationMock {
    /// @dev Returns the Version of the Implementation
    function getMockVersion() external pure returns (uint);
}
