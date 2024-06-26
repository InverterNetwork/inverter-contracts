pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";
import {InverterBeaconProxy} from "src/factories/beacon/InverterBeaconProxy.sol";
import {TransactionForwarder} from
    "src/external/forwarder/TransactionForwarder.sol";

/**
 * @title TransactionForwarder Deployment Script
 *
 * @dev Script to deploy a new TransactionForwarder and link it to a beacon.
 *
 * @author Inverter Network
 */
contract DeployAndSetUpTransactionForwarder is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    /// @notice Creates the implementation, beacon and proxy of the transactionForwarder
    /// @return implementation The implementation of the TransactionForwarder that will be referenced in the beacon
    /// @return beacon The beacon that points to the implementation
    /// @return forwarder The proxy that will be used for the real transactionForwarder
    function run()
        external
        returns (address implementation, address beacon, address forwarder)
    {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the transaction forwarder.
            implementation = address(
                new TransactionForwarder("Inverter Transaction Forwarder")
            );

            // Deploy the beacon.
            beacon = address(new InverterBeacon(1));

            // Upgrade the Beacon to the chosen implementation
            InverterBeacon(beacon).upgradeTo(address(implementation), 1, false);

            forwarder = address(new InverterBeaconProxy(InverterBeacon(beacon)));
        }
        vm.stopBroadcast();

        // Log
        console2.log("Deployment of implementation at address ", implementation);
        console2.log("Deployment of Beacon at address ", beacon);
        console2.log(
            "Deployment of transactionForwarder proxy at address ", forwarder
        );
    }
}
