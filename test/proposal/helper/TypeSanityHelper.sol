// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

contract TypeSanityHelper is Test {
    address private _self;

    constructor(address self) {
        _self = self;
    }

    //--------------------------------------------------------------------------------
    // Helpers

    function assumeElemNotInSet(address[] memory set, address elem) public {
        for (uint i; i < set.length; ++i) {
            vm.assume(elem != set[i]);
        }
    }

    //--------------------------------------------------------------------------------
    // Types for Proposal
    // Contract: Proposal.sol

    function assumeValidProposalId(uint id) public {
        vm.assume(id != 0);
    }

    //--------------------------------------------------------------------------------
    // Types for Module
    // Contract: base/ModuleManager.sol

    mapping(address => bool) moduleCache;

    function assumeValidModules(address[] memory modules) public {
        for (uint i; i < modules.length; ++i) {
            assumeValidModule(modules[i]);

            // Assume module unique.
            vm.assume(!moduleCache[modules[i]]);

            // Add module to cache.
            moduleCache[modules[i]] = true;
        }
    }

    function assumeValidModule(address module) public {
        address[] memory invalids = createInvalidModules();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(module != invalids[i]);
        }
    }

    function createInvalidModules() public view returns (address[] memory) {
        address[] memory invalids = new address[](2);

        invalids[0] = address(0);
        invalids[1] = _self;

        return invalids;
    }

    //--------------------------------------------------------------------------------
    // Types for Funder
    // Contract: base/FunderManager.sol

    function assumeValidFunders(address[] memory funders) public {}

    // @todo nejc, mp: FunderManager Type Sanity check- and creater functions.
}
