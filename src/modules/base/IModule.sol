// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";

interface IModule {
    struct Metadata {
        uint majorVersion;
        uint minorVersion;
        string url;
        string title;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Module__CallerNotAuthorized();

    /// @notice Function is only callable by the proposal.
    error Module__OnlyCallableByProposal();

    /// @notice Given proposal address invalid.
    error Module__InvalidProposalAddress();

    /// @notice Given metadata invalid.
    error Module__InvalidMetadata();

    /// @notice Proposal callback triggered failed.
    /// @param funcSig The signature of the function called.
    error Module_ProposalCallbackFailed(string funcSig);

    /// @notice init2 was called again for a module
    error Module__CannotCallInit2Again();

    /// @notice the dependency data passed to init2 was not in the correct format
    ///         or there was no dependency for the particular module
    error Module__NoDependencyOrMalformedDependencyData();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice The module's initializer function.
    /// @dev CAN be overriden by downstream contract.
    /// @dev MUST call `__Module_init()`.
    /// @param proposal The module's proposal instance.
    /// @param metadata The module's metadata.
    /// @param configdata Variable config data for specific module
    ///                   implementations.
    function init(
        IProposal proposal,
        Metadata memory metadata,
        bytes memory configdata
    ) external;

    /// @notice Second initialization function of the module to take care of dependencies.
    /// @param proposal The module's proposal instance.
    /// @param configdata Variable config data for specific module
    ///                   implementations.
    function init2(IProposal proposal, bytes memory configdata) external;

    /// @notice Returns the module's identifier.
    /// @dev The identifier is defined as the keccak256 hash of the module's
    ///      abi packed encoded major version, url and title.
    /// @return The module's identifier.
    function identifier() external view returns (bytes32);

    /// @notice Returns the module's version.
    /// @return The module's major version.
    /// @return The module's minor version.
    function version() external view returns (uint, uint);

    /// @notice Returns the module's URL.
    /// @return The module's URL.
    function url() external view returns (string memory);

    /// @notice Returns the module's title.
    /// @return The module's title.
    function title() external view returns (string memory);

    /// @notice Returns the module's {IProposal} proposal instance.
    /// @return The module's proposal.
    function proposal() external view returns (IProposal);
}
