// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TypeSanityHelper is Test {
    address private _self;

    constructor(address self) {
        _self = self;
    }

    //--------------------------------------------------------------------------------
    // Helpers

    function assumeElemNotInSet(address[] memory set, address elem)
        public
        pure
    {
        for (uint i; i < set.length; ++i) {
            vm.assume(elem != set[i]);
        }
    }

    //--------------------------------------------------------------------------------
    // Types for Orchestrator
    // Contract: Orchestrator.sol

    function assumeValidOrchestratorId(uint id) public pure {
        vm.assume(id != 0);
    }

    //--------------------------------------------------------------------------------
    // Types for Module
    // Contract: base/ModuleManager.sol

    uint8 private constant MAX_MODULES = 128;

    mapping(address => bool) moduleCache;

    function assumeValidModules(address[] memory modules) public {
        vm.assume(modules.length <= MAX_MODULES);
        for (uint i; i < modules.length; ++i) {
            assumeValidModule(modules[i]);

            // Assume module unique.
            vm.assume(!moduleCache[modules[i]]);

            // Add module to cache.
            moduleCache[modules[i]] = true;
        }
    }

    function assumeValidModule(address module) public view {
        address[] memory invalids = createInvalidModules();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(module != invalids[i]);
        }
    }

    function createInvalidModules() public view returns (address[] memory) {
        address[] memory invalids = new address[](3);

        invalids[0] = address(0);
        invalids[1] = _self;

        return invalids;
    }

    //--------------------------------------------------------------------------------
    // Types for Funder
    // Contract: base/FunderManager.sol

    function assumeValidFunders(address[] memory funders) public {}
}
