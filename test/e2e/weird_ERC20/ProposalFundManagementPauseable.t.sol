// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

// Mocks
import {PauseableToken} from "test/utils/mocks/weird_ERC20/PauseableToken.sol";

/**
 * @title ProposaFundManagementPauseable
 *
 * @dev Pauseable token has the ability to pause, preventing use of approve,
 *      transfer and transferFrom functions. Contract can than be unpaused
 *      again, allowing the usual functionality of aforementioned functions.
 *      Examples of popular pauseable tokens are BNB, AAVE, ZRX, SNX, COMP
 *      and many more. Overall pauseable tokens are widely present in
 *      crypto space.
 * @dev For this test we pause token, before making deposit, either calling
 *      approve before pausing or after. In both cases deposit is expected to
 *      fail, but succeed when the token is unpaused, without the need to
 *      approve it again (in Bobs case). We then pause the token again,
 *      expacting withdrawal to fail but succeed when the token is unpaused,
 *      while making all further withdrawals possible, giving correct amounts
 *      to their respective recipients.
 * @author byterocket
 */

contract ProposaFundManagementPauseable is E2eTest {
    address alice = address(0xA11CE);
    address bob = address(0x606);

    // @note Pauseable token allows disabling of approve, transfer and
    //       transferFrom functions. Those functions can be re-enabled by owner.
    // @dev approve() is overwriten in Pausable as well so it won't work when
    // token is on pause.
    PauseableToken token = new PauseableToken(10e18);

    function test_e2e_ProposalFundManagement() public {
        // address(this) creates a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the proposal.
        // It's best, if the owner deposits them right after deployment.
        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);

        token.approve(address(proposal), initialDeposit);
        proposal.deposit(initialDeposit);

        // Mint some tokens to alice and bob in order to fund the proposal.
        token.mint(alice, 1000e18);
        token.mint(bob, 5000e18);

        // Token got Paused.
        token.stop();
        assertFalse(token.isLive());

        // Alice funds the proposal with 1k tokens.
        vm.startPrank(alice);
        {
            // Token can't be approved when on pause.
            try token.approve(address(proposal), 1000e18) {
                proposal.deposit(1000e18);
                // If calls were successful, test should fail.
                assertTrue(false);
            } catch {
                // Token is Unpaused again.
                vm.stopPrank();
                token.start();
                assertTrue(token.isLive());
                // Another attempt at approving should be successful.
                vm.startPrank(alice);
                {
                    // Approve tokens to proposal.
                    token.approve(address(proposal), 1000e18);
                    // Deposit tokens, i.e. fund the proposal.
                    proposal.deposit(1000e18);
                }
                vm.stopPrank();
                // After the deposit, alice received some amount of receipt tokens
                // from the proposal.
                assertTrue(proposal.balanceOf(alice) > 0);
            }
        }

        // Bob funds the proposal with 5k tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to proposal.
            token.approve(address(proposal), 5000e18);
        }
        vm.stopPrank();

        // Token got Paused.
        token.stop();
        assertFalse(token.isLive());

        vm.startPrank(bob);
        {
            // Token can't be deposited when on pause.
            try proposal.deposit(5000e18) {
                assertTrue(proposal.balanceOf(bob) > 0);
                // If deposit was successful, test should fail.
                assertTrue(false);
            } catch {
                // Token is Unpaused again.
                vm.stopPrank();
                token.start();
                assertTrue(token.isLive());
                // Another attempt at depositing should be successful.
                vm.startPrank(bob);
                {
                    // Deposit tokens, i.e. fund the proposal.
                    proposal.deposit(5000e18);
                }
                vm.stopPrank();
                // After the deposit, bob received some amount of receipt tokens
                // from the proposal.
                assertTrue(proposal.balanceOf(bob) > 0);
            }
        }

        // If the proposal spends half their tokens, i.e. for a milestone,
        // alice and bob are still able to withdraw their respective leftover
        // of the tokens.
        // Note that we simulate proposal spending by just burning tokens.
        token.burn(address(proposal), token.balanceOf(address(proposal)) / 2);

        // Token got Paused.
        token.stop();
        assertFalse(token.isLive());

        // Alice is not able to withdraw half her funded tokens
        // as long token is Paused. After that withdraw is possible again.
        vm.startPrank(alice);
        {
            try proposal.withdraw(proposal.balanceOf(alice)) {
                // If withdraw is successful, test should fail.
                assertTrue(false);
            } catch {
                // Alice gets in unblocked again
                vm.stopPrank();
                token.start();
                assertTrue(token.isLive());
                // Another attempt at withdrawing should be successful.
                vm.startPrank(alice);
                {
                    proposal.withdraw(proposal.balanceOf(alice));
                }
                vm.stopPrank();
                // Verify alice balances are correct.
                assertEq(token.balanceOf(alice), 500e18);
            }
        }

        // Bob is also able to withdraw half of his funded tokens.
        vm.startPrank(bob);
        {
            proposal.withdraw(proposal.balanceOf(bob));
            assertEq(token.balanceOf(bob), 2500e18);
        }
        vm.stopPrank();

        // After redeeming all their proposal function tokens, the tokens got
        // burned.
        assertEq(proposal.balanceOf(alice), 0);
        assertEq(proposal.balanceOf(bob), 0);
    }
}