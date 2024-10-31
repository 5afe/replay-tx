# Replay Safe Transaction

This repository provides a script for building a Safe{Wallet} Transaction Builder bundle from a previously executed transaction.

**Disclaimer**: Always verify transactions before executing them! The script could have bugs that inadvertently build incorrect bundles.

## Requirements

- `jq`
- `curl`

## Usage

To replay a Safe transaction for Safe `eth:0x5afe5afE5afE5afE5afE5aFe5aFe5Afe5Afe5AfE` with nonce `42`, run:

```sh
bash replay-tx.sh eth:0x5afe5afE5afE5afE5afE5aFe5aFe5Afe5Afe5AfE 42 -o tx-bundle.json
```

This will create a `tx-bundle.json` file that can be imported into the Safe{Wallet} transaction builder interface.
