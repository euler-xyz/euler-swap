# Invariants
echidna:
	echidna test/enigma-dark-invariants/Tester.t.sol --contract Tester --config ./test/enigma-dark-invariants/_config/echidna_config.yaml --corpus-dir ./test/enigma-dark-invariants/_corpus/echidna/default/_data/corpus

echidna-assert:
	echidna test/enigma-dark-invariants/Tester.t.sol --contract Tester --test-mode assertion --config ./test/enigma-dark-invariants/_config/echidna_config.yaml --corpus-dir ./test/enigma-dark-invariants/_corpus/echidna/default/_data/corpus

echidna-explore:
	echidna test/enigma-dark-invariants/Tester.t.sol --contract Tester --test-mode exploration --config ./test/enigma-dark-invariants/_config/echidna_config.yaml --corpus-dir ./test/enigma-dark-invariants/_corpus/echidna/default/_data/corpus

# Invariants
echidna-docker:
	echidna test/enigma-dark-invariants/Tester.t.sol --contract Tester --config ./test/enigma-dark-invariants/_config/echidna_config_runner.yaml --corpus-dir ./test/enigma-dark-invariants/_corpus/echidna/default/_data/corpus


# Medusa
medusa:
	medusa fuzz --config ./medusa.json