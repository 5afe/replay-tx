#!/usr/bin/env bash

set -euo pipefail

fail() {
	local msg="$1"
	echo "ERROR: $1" 1>&2
	exit 1
}

if ! command -v jq &>/dev/null; then
	fail "'jq' command is missing"
fi
if ! command -v curl &>/dev/null; then
	fail "'curl' command is missing"
fi


addr=
nonce=
output=
while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			cat <<EOF
Replay Safe transaction.

USAGE:
    $0 [-o|--output FILE] ADDR NONCE

OPTIONS:
    -h|--help           Display this output message
    -o|--output FILE    The file to output the transaction builder JSON to.
                        If left unset, will output to standard out.

ARGUMENTS:
    ADDR                The Safe with the transaction to replay.
    NONCE               The nonce to replay

EXAMPLES:
    Generate Safe transaction builder JSON document and print it.
        $0 eth:0xcA771eda0c70aA7d053aB1B25004559B918FE662 42

    Generate Safe transaction builder JSON document and save it to 'tx.json'.
        $0 eth:0xcA771eda0c70aA7d053aB1B25004559B918FE662 42
EOF
			;;
		-o|--output)
			if [[ $# -lt 2 ]]; then
				fail "missing argument for '-o|--output' option"
			fi
			shift
			output="$1"
			;;
		*)
			if [[ -z "$addr" ]]; then
				addr="$1"
			elif [[ -z "$nonce" ]]; then
				nonce="$1"
			else
				fail "unexpected argument '$1'"
			fi
			;;
	esac
	shift
done

if [[ -z "$addr" ]] || [[ -z "$nonce" ]]; then
	fail "missing Safe address and nonce arguments"
fi
if ! [[ "$addr" =~ ^[a-z]+:0x[0-9a-fA-F]{40}$ ]]; then
	fail "invalid Safe address"
fi
if ! [[ "$nonce" =~ [0-9]+ ]]; then
	fail "invalid nonce"
fi

case "$(echo "$addr" | cut -d ':' -f1)" in
	eth)
		network=mainnet
		chain_id=1
		;;
	# TODO(nlordell): add more networks...
	*) fail "unknown network" ;;
esac
safe="$(echo "$addr" | cut -d ':' -f2)"

txs="$(
	curl -s --fail \
		-H "Accept: application/json" \
		"https://safe-transaction-$network.safe.global/api/v1/safes/$safe/multisig-transactions/?nonce=$nonce"
)"

if [[ "$(echo "$txs" | jq .count)" -ne 1 ]]; then
	fail "could not find Safe transaction"
fi

tx="$(echo "$txs" | jq '.results[0]')"
is_multisend="$(
	echo "$tx" | jq '
		.to == "0x40A2aCCbd92BCA938b02010E17A5b8929b49130D" and
		.operation == 1 and
		.dataDecoded.method == "multiSend" and
		(.dataDecoded.parameters | length) == 1 and
		.dataDecoded.parameters[0].type == "bytes" and
		(.dataDecoded.parameters[0].valueDecoded | type) == "array"
	'
)"

if [[ "$is_multisend" == "true" ]]; then
	calls="$(echo "$tx" | jq '.dataDecoded.parameters[0].valueDecoded')"
else
	calls="$(echo "$tx" | jq '[{ to, operation, value, data, dataDecoded }]')"
fi

has_delegatecall="$(echo "$calls" | jq 'any(.operation == 1)')"
if [[ "$has_delegatecall" == "true" ]]; then
	fail "delegate calls not supported"
fi

builder="$(
	echo "$calls" | jq '{
		version: "1.0",
		chainId: "'$chain_id'",
		createdAt: 0,
		meta: {
			name: "Replay transaction nonce '$nonce'",
			description: "",
			txBuilderVersion: "",
			createdFromSafeAddress: "'$safe'",
			createdFromOwnerAddress: "",
			checksum: "0x0000000000000000000000000000000000000000000000000000000000000000"
		},
		transactions: [
			.[] | if .dataDecoded then {
				to,
				value,
				data: null,
				contractMethod: {
					inputs: [
						.dataDecoded.parameters[] | {
							internalType: .type,
							name,
							type,
						}
					],
					name: .dataDecoded.method,
					paybale: (.value != "0")
				},
				contractInputsValues: ([
					.dataDecoded.parameters[] | {
						key: .name,
						value,
					}
				] | from_entries),
			} else {
				to,
				value,
				data,
				contractMethod: null,
				contractInputsValues: null,
			} end
		],
	}'
)"

if [[ -z "$output" ]]; then
	echo "$builder" | jq .
else
	echo "$builder" | jq . > "$output"
fi
