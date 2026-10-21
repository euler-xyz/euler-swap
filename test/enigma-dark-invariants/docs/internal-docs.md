# Internal Documentation for the Euler Earn Enigma Dark Invariant Testing Suite

## Table of Contents

1. [Running the Suite](#running-the-suite)

   - Prerequisites
   - Starting the Suite
   - Configurations

2. [Property Formats](#property-formats)

   - Invariants
   - Postconditions
     - Global Postconditions (GPOST)
     - Handler-Specific Postconditions (HSPOST)

3. [Handlers: Adding Support for New Functions](#handlers-adding-support-for-new-functions)

   - Overview
   - Adding New Functions
   - Testing New Functions

4. [Debugging Broken Properties](#debugging-broken-properties)
   - Logging & Output
   - Crytic to Foundry Test Helper
   - Steps to Reproduce an Echidna Error Inside the Foundry Wrapper

## Running the Suite

- **Prerequisites**:

  - Ensure that all protocol dependencies have been installed:

    ```sh
    cp .env.example .env

    forge install
    ```

  - Make sure the latest version of **Echidna** is installed. If it is not installed, you can follow the guide [HERE](https://github.com/crytic/echidna?tab=readme-ov-file#installation) to install it.

  <br />

- **Starting the Suite**: The suite is able to check the invariants and postconditions of the Euler Earn protocol. For that it uses two different modes, property mode and assertion mode respectively.

  - **Property Mode**: Checks protocol invariants. Run with:
    ```sh
    make echidna
    ```
  - **Assertion Mode**: Checks protocol postconditions. Run with:

    ```sh
    make echidna-assert
    ```

  - **Extra**: Run the suites without checking for properties, only increasing corpus size and coverage. Run with:
    ```sh
    make echidna-explore
    ```

  <br />

- **Configurations**: The suite configuration can be found in the [echidna_config.yaml](../_config/echidna_config.yaml) file. This file contains the configuration for the Echidna testing tool, the following are the most important parameters of the configuration:

  - **seqLen**: Defines the number of calls in each test sequence.
  - **maxDepth**: Sets the total number of test sequences to execute.
  - **coverage**: Enables coverage tracking, stored in the directory specified by `corpusDir`.
  - **corpusDir**: Directory for saving coverage data. In this suite, coverage is saved in `tests/invariants/_corpus/echidna/default/_data/corpus`.
  - **workers**: Sets the number of parallel threads for Echidna, ideally close to the machine's CPU thread count for optimal performance.
    <br />

## Property Formats

As mentioned on the public documentation this suite framework spins around to types of properties, **invariants** and **postconditions**. The following section will provide a detailed explanation of each type of property and how they are implemented.

### Invariants

- **Definition**: Invariants are properties that must hold true across all states of the system. These are checked when the tool runs under property-mode, making echidna call all public functions starting with `echidna_` and making sure the assertions in those do not fail. These checks happen in between every call inside test sequences.
- **Example**: BASE_INVARIANT_A

  - **Spec**: totalAssetsDeposited + interestLeft >= totalAllocated.
  - **Implementation**: `BaseInvariants::assert_INV_ASSETS_A`

    ```solidity
    function assert_INV_ASSETS_A() internal {
      (,, uint168 interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();

      uint256 totalAssetsDeposited = eulerEulerEarnVault.totalAssetsDeposited();

      if (eulerEulerEarnVault.totalAssetsAllocatable() - totalAssetsDeposited - interestLeft == 0) {
        assertGe(totalAssetsDeposited + interestLeft, eulerEulerEarnVault.totalAllocated(), INV_ASSETS_A);
      }
    }
    ```

    Every implementation of an invariant must be called inside its wrapper `echidna_**` function on the `Invariants.sol` file, as shown in the following code snippet:

    ```solidity
    function echidna_INV_ASSETS_INVARIANTS() public returns (bool) {
      assert_INV_ASSETS_A();
      assert_INV_ASSETS_D();

      uint256 sumStrategiesAllocated;
      for (uint256 i; i < strategies.length; i++) { /// <--- Looping through all strategies tokens,
        IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(strategies[i]);
        if (strategy.status == IEulerEarn.StrategyStatus.Active) {
          sumStrategiesAllocated += eulerEulerEarnVault.getStrategy(strategies[i]).allocated;
        }
      }

      assert_INV_ASSETS_B(sumStrategiesAllocated);
      return true;
    }
    ```

- **Implementation Guide**:
  - Define core properties of the protocol (e.g., balance constraints, liquidity checks, internal accounting accuracy).
  - Keep assertions clear and straightforward. If looping through users, assets, or reserves, aim for simplicity—avoid excessive or complex logic to maintain efficiency and readability (check example above looping through the suite actors).
  - Minimize redundancy by ensuring invariants don’t overlap too heavily with each other. However, certain degree of overlap can be beneficial for covering more scenarios, so consider strategic overlaps to maximize checks coverage.

### Postconditions

- **Definition**: Postconditions are properties that must hold true following specific actions or interactions within a test sequence. They help ensure that each action in the sequence produces a valid protocol state, focusing on targeted outcomes rather than overall system-wide conditions. Unlike invariants, which are checked consistently across states, postconditions are enforced at designated points. These points include the end of each handler call (for handler-specific postconditions) or at the end of the `_after` hook (for global postconditions), validating the expected results of specific actions.

  As the public documentation states, these checks are performed in assertion-mode, where echidna report a failing alert after detecting a `Panic(1)` error coming from a failed `assert` statement.

- **Categories**: These postconditions can fall into two categories, the global postconditions and the handler-specific postconditions. The global postconditions (GPOST) are checked at the end of each test sequence using the `_after` hook, while the handler-specific postconditions (HSPOST) are checked at the end of specific handler calls.

- **Example GPOST**: GPOST_BASE_A

  - **Spec**: lastHarvestTimestamp increases monotonically.
  - **Implementation**: `DefaultBeforeAfterHooks::assert_GPOST_BASE_A`

    ```solidity
    function assert_GPOST_BASE_A() internal {
      assertGe(defaultVarsAfter.lastHarvestTimestamp, defaultVarsBefore.lastHarvestTimestamp, GPOST_BASE_A);
    }
    ```

    Every global postcondition must be called at the end of the `_after` hook in the `_checkPostConditions` function, as shown in the following code snippet:

    ```solidity
    function _checkPostConditions() internal {
      // Implement post conditions here
      ...

      // BASE
      assert_GPOST_BASE_A(); /// <--- Global postcondition execution

      ...
    }
    ```

- **Example HSPOST**: HSPOST_USER_A

  - **Spec**: After a deposit or mint, the amount should be credited to the cash reserve.
  - **Implementation**: At the end of the `deposit` handler, the postcondition is checked.

    ```solidity
    function deposit(uint8 i) external setup {
      bool success;
      bytes memory returnData;

      ... /// <--- variable caching, actor-call, etc. summarized for brevity

      if (success) {
        _after();

        // POST-CONDITIONS
        /// @dev HSPOST_USER_A
        assertEq(defaultVarsBefore.balance + assets, defaultVarsAfter.balance, HSPOST_USER_A);
      }
    }
    ```

- **Implementation Guide**:
  - Identify key outcomes or state changes that should result from each action (e.g., balance updates, collateral adjustments, interest accruals).
  - Aim to complement invariants with global postconditions, ensuring that properties that are not possible to be implemented as invariants are still covered.
    <br />

## Handlers: Adding Support for New Functions

- **Overview**: As the public documentation states, handlers act as a kind of middleware layer between the tooling and the protocol. That is why when new features are added to the protocol or this one is upgraded, new handler functions must be either added or updated to support the new features. The following section will provide a detailed explanation of how to add support for new functions in handlers.
- **Adding New Functions**: Let's take the example of an upgrade. The following steps show a guide through the process of adding support for these new functions in the handlers:

  - **Identify the Handler**: Determine which handler contract will be responsible for the new functions.

  - **Identify the parameters**: Determine which parameters are needed for the actions, which ones can be randomized, which ones should be clamped and which ones should be taken from a finite set like a helper storage array.

  - **Identify if the action is permissioned or permissionless**: If the action is permissioned, using actors as proxy is not needed since the suite is setup as the owner so a direct call to the handler is enough. If the action is permissionless, an actor-proxied call must be used along with the `setup` actor selection modifier. The following code is how the `deposit` implementation would look like:

    - Function should be called by an actor so the `setup` modifier and a proxied call to the protocol are used.
    - The function should be called between the `_before` and `_after` hooks to ensure values are cached for postconditions to be checked properly.

    ```solidity
    function deposit(
      uint256 assets,
      uint8 i
    ) external setup {
      bool success; /// <--- Variables to store the success of the call and return data
      bytes memory returnData;

      address receiver = _getRandomActor(i); /// <--- Random receiver actor selection

      _before(); /// <--- Before hook
      (success, returnData) = actor.proxy(target, /// <--- Proxied call to the protocol
        abi.encodeWithSelector(
          IERC4626.deposit.selector,
          assets,
          receiver
        ));

      if (success) {
        _after(); /// <--- After hook on success
        ...
      }

    }
    ```

  - **Update Postconditions**: If the new functions introduce changes to the protocol state, update the postconditions to reflect these changes.
    <br />

- **Testing**: After adding the new handler functions and updating the postconditions, run the tooling to make sure the new logic is being covered and work correctly. You can check for html coverage reports inside `echidna/default/_data/corpus` directory.
  <br />

## Debugging Broken Properties

- **Logging & Output**: While running, Echidna displays a terminal UI that reports the status of properties—either passing or failing—along with relevant call traces. When a property fails, some threads initiate a "shrinking" process to simplify the call trace, making debugging easier. The amount of shrinking effort can be adjusted in the `echidna_config.yaml` file using the `shrinkLimit` parameter.
  After shrinking completes for a failing property, the suite can be stopped with `Ctrl+C`. Corpus and coverage data are saved automatically, and the dashboard's information is output to the command line, allowing to copy the minimized call trace for further debugging with Foundry wrapper tests.

- **Crytic to foundry test helper**: `CryticToFoundry` file serves as a call trace reproducer where call traces from echidna output can be debugged easily. The following is an example of how to use the helper for a failing property:

  ```solidity
  function test_INV_ASSETS_INVARIANTS_1() public {
    Tester.donateUnderlying(1 ether, 0);
    Tester.simulateYieldAccrual(1 ether, 0);
    Tester.addStrategy(1, 0);
    Tester.toggleStrategyEmergencyStatus(0);
    Tester.toggleStrategyEmergencyStatus(0);
    _delay(2 weeks);
    console.log(block.timestamp);
    echidna_INV_ASSETS_INVARIANTS();
  }
  ```

- **Steps to reproduce an Echidna error inside the Foundry wrapper**:
  - Copy the call trace from the Echidna output.
  - Initiate the `[echidna-trace-parser](https://github.com/Enigma-Dark/echidna-trace-parser)` tool.
  - Paste the call trace into the tool.
  - Hit enter to generate the Foundry wrapper test.
  - Copy the generated test and paste it into the `CryticToFoundry` file.
  - Run the test and debug the failing property using foundry verbose output `-vvvv`.

## CI Setup

- **Overview**: The suite is integrated into the CI pipeline of the protocol to ensure that the properties are checked consistently with every updates. Once the suite has been tuned to be fast and efficient, it can be integrated in the development cycle to catch bugs. Once optimized for speed and efficiency, the suite can be incorporated into the development lifecycle to identify bugs early. The following rules should be followed to configure the CI pipeline for effective integration of the suite:

  1. **Corpus Directory Management**:
     After completing the invariant testing engagement, a `corpus` directory is generated with the coverage data and reproducers. This directory represents hundreds of CPU hours of refinement and is valuable to make the tool run efficiently. Since an attacker could use the contents of this directory to quickly identify attack vectors and vulnerable code it is excluded from the files pushed to the github repository. The `corpus` directory is independetly stored in a private repository, and the CI pipeline has permissions and is configured to pull from the private repository to get the `corpus` directory and run the suite with the coverage data.
  2. **Ongoing Fuzzing Campaigns**:
     For every code update, new feature, or public release, the fuzzing campaign should execute for at least 24 hours, starting with the existing `corpus` directory. This process ensures the corpus remains up to date with recent changes and verifies the suite continues to validate critical properties.
  3. **Corpus Updates**:
     After the fuzzing campaign, the updated corpus directory should be pushed back to the private repository, maintaining a continuously evolving corpus.

  > Note: The CI pipeline for the public repository is configured to pull the corpus directory securely from the private repository, which requires proper permissions and secrets.

- **Setup**: Follow these steps to set up CI pipeline permissions and integrate the fuzzing suite effectively:

  1. **Create a private repository**:
     - Name the repository following this convention: `protocol-name-suite-corpus` (e.g., `euler-earn-suite-corpus`).
     - This repository should be owned by the same organization as the public repository.
  2. **Initialize the corpus repository**:
     - Navigate to the local `corpus` directory, initialize a git repository, add the remote origin and push the contents to the private repository.
  3. **Generate SSH Keys**:
     - Create a new RSA key pair:
       ```sh
       ssh-keygen -t rsa -b 4096 -C "
       ```
     - Add the public key as a read-only deployment key in the private repository, using the variable name `DEPLOY_CORPUS_KEY`.
     - Save the private key as a GitHub Actions secret in the public repository under the name `SSH_CORPUS_PRIVATE_KEY`.

- **CI Job Overview**:
  The `enigma-invariants.yml` job has been configured to pull the corpus directory from the private repository and run the suite efficiently with the coverage data. Additionally, a new configuration file, `echidna_config_ci.yaml`, has been derived from the suite's original `echidna_config.yaml`. This CI-specific configuration has been optimized to utilize the `corpus` directory and coverage data efficiently while reducing execution time.

  The adjustments include a more moderate number of runs and sequence lengths to improve the suite's performance in the CI pipeline. Since the primary goal in this context is to validate against existing coverage, the suite can afford shorter execution durations and reduced sequence complexity.

  - `testLimit` reduced to 50000
  - `seqLen` reduced to 200
  - `shrinkLimit` reduced to 1500
  - `corpusDir` set to the `corpus` directory created when cloning the private repository.
