#!/bin/bash

set -e

DEMO_HOME=$(pwd)
script_name=`basename "$0"`

# Create a helper function to address the first vault node
function vault_1() {
    (export VAULT_ADDR=http://127.0.0.1:8200 && vault $@)
}

# Create a helper function to address the second vault node
function vault_2() {
    (export VAULT_ADDR=http://127.0.0.2:8200 && vault $@)
}

# Create a helper function to address the third vault node
function vault_3() {
    (export VAULT_ADDR=http://127.0.0.3:8200 && vault $@)
}

# Create a helper function to address the fourth vault node
function vault_4() {
    (export VAULT_ADDR=http://127.0.0.4:8200 && vault $@)
}

function stop() {
  service_count=$(pgrep -f $(pwd)/config | wc -l | tr -d '[:space:]')

  printf "\n%s" \
    "Found $service_count Vault services" \
    ""

  if [ $service_count != "0" ] ; then
    printf "\n%s" \
      "Stopping $service_count Vault services" \
      ""

    pkill -f $(pwd)/config
  fi
}

function loopback_exists_at_address() {
  echo $(ifconfig lo0 | grep $1 || true) | tr -d '[:space:]'
}

function clean() {

  printf "\n%s" \
    "Cleaing up the HA cluster. Removing:" \
    " - local loopback address for [vault_2], [vault_3], and [vault_4[" \
    " - configuration files" \
    " - raft storage directory" \
    " - log files" \
    " - unseal / recovery keys" \
    ""

  for loopback_address in "127.0.0.2" "127.0.0.3" "127.0.0.4" ; do
    loopback_exists=$(loopback_exists_at_address $loopback_address)

    if [[ $loopback_exists != "" ]] ; then
      printf "\n%s" \
        "Removing local loopback address: $loopback_address (sudo required)" \
        ""

      sudo ifconfig lo0 -alias $loopback_address
    fi
  done

  for config_file in $DEMO_HOME/config-vault_1.hcl $DEMO_HOME/config-vault_2.hcl $DEMO_HOME/config-vault_3.hcl $DEMO_HOME/config-vault_4.hcl ; do
    if [[ -f "$config_file" ]] ; then
      printf "\n%s" \
        "Removing configuration file $config_file"

      rm $config_file
    fi
  done

  for raft_storage in $DEMO_HOME/raft-vault_2 $DEMO_HOME/raft-vault_3 $DEMO_HOME/raft-vault_4 ; do
    if [[ -d "$raft_storage" ]] ; then
    printf "\n%s" \
        "Removing raft storage file $raft_storage"

      rm -rf $raft_storage
    fi
  done

  for key_file in $DEMO_HOME/unseal_key-vault_1 $DEMO_HOME/recovery_key-vault_2 ; do
    if [[ -f "$key_file" ]] ; then
      printf "\n%s" \
        "Removing key $key_file"

      rm $key_file
    fi
  done

  for token_file in $DEMO_HOME/root_token-vault_1 $DEMO_HOME/root_token-vault_2 ; do
    if [[ -f "$token_file" ]] ; then
      printf "\n%s" \
        "Removing key $token_file"

      rm $token_file
    fi
  done
  
  for vault_log in $DEMO_HOME/vault_1.log $DEMO_HOME/vault_2.log $DEMO_HOME/vault_3.log $DEMO_HOME/vault_4.log ; do
    if [[ -f "$vault_log" ]] ; then
      printf "\n%s" \
        "Removing log file $vault_log"

      rm $vault_log
    fi
  done

  printf "\n%s" \
    "Clean complete" \
    ""
}

function status {
  service_count=$(pgrep -f $(pwd)/config | wc -l | tr -d '[:space:]')

  printf "\n%s" \
    "Found $service_count Vault services" \
    ""

  if [[ "$service_count" != 4 ]] ; then
    printf "\n%s" \
    "Unable to find all Vault services" \
    ""
  fi

  printf "\n%s" \
    "[vault_1] status" \
    ""
  vault_1 status || true

  printf "\n%s" \
    "[vault_2] status" \
    ""
  vault_2 status || true

  printf "\n%s" \
    "[vault_3] status" \
    ""
  vault_3 status || true

  printf "\n%s" \
    "[vault_4] status" \
    ""
  vault_4 status || true

  sleep 2
}

function create_network {

  printf "\n%s" \
    "[vault_2] Enabling local loopback on 127.0.0.2 (requires sudo)" \
    ""

  sudo ifconfig lo0 alias 127.0.0.2

  printf "\n%s" \
    "[vault_3] Enabling local loopback on 127.0.0.3 (requires sudo)" \
    ""

  sudo ifconfig lo0 alias 127.0.0.3

  printf "\n%s" \
    "[vault_4] Enabling local loopback on 127.0.0.4 (requires sudo)" \
    ""

  sudo ifconfig lo0 alias 127.0.0.4

}

function create_config {

  printf "\n%s" \
    "[vault_1] Creating configuration" \
    "  - creating $DEMO_HOME/config-vault_1.hcl"

  rm -rf config-vault_1.hcl

  tee $DEMO_HOME/config-vault_1.hcl 1> /dev/null <<EOF
    storage "inmem" {}
    listener "tcp" {
      address = "127.0.0.1:8200"
      tls_disable = true
    }
EOF

  printf "\n%s" \
    "[vault_2] Creating configuration" \
    "  - creating $DEMO_HOME/config-vault_2.hcl" \
    "  - creating $DEMO_HOME/raft-vault_2"

  rm -rf config-vault_2.hcl
  rm -rf $DEMO_HOME/raft-vault_2
  mkdir -pm 0755 $DEMO_HOME/raft-vault_2

  tee $DEMO_HOME/config-vault_2.hcl 1> /dev/null <<EOF
  storage "raft" {
    path    = "$DEMO_HOME/raft-vault_2/"
    node_id = "vault_2"
  }
  listener "tcp" {
    address = "127.0.0.2:8200"
    cluster_address = "127.0.0.2:8201"
    tls_disable = true
  }
  seal "transit" {
    address            = "http://127.0.0.1:8200"
    # token is read from VAULT_TOKEN env
    # token              = ""
    disable_renewal    = "false"

    // Key configuration
    key_name           = "unseal_key"
    mount_path         = "transit/"
  }
  disable_mlock = true
  cluster_addr = "http://127.0.0.2:8201"
EOF

  printf "\n%s" \
    "[vault_3] Creating configuration" \
    "  - creating $DEMO_HOME/config-vault_3.hcl" \
    "  - creating $DEMO_HOME/raft-vault_3"

  rm -rf config-vault_3.hcl
  rm -rf $DEMO_HOME/raft-vault_3
  mkdir -pm 0755 $DEMO_HOME/raft-vault_3

  tee $DEMO_HOME/config-vault_3.hcl 1> /dev/null <<EOF
  storage "raft" {
    path    = "$DEMO_HOME/raft-vault_3/"
    node_id = "vault_3"
  }
  listener "tcp" {
    address = "127.0.0.3:8200"
    cluster_address = "127.0.0.3:8201"
    tls_disable = true
  }
  seal "transit" {
    address            = "http://127.0.0.1:8200"
    # token is read from VAULT_TOKEN env
    # token              = ""
    disable_renewal    = "false"

    // Key configuration
    key_name           = "unseal_key"
    mount_path         = "transit/"
  }
  disable_mlock = true
  cluster_addr = "http://127.0.0.3:8201"
EOF

  printf "\n%s" \
    "[vault_4] Creating configuration" \
    "  - creating $DEMO_HOME/config-vault_4.hcl" \
    "  - creating $DEMO_HOME/raft-vault_4"

  rm -rf config-vault_4.hcl
  rm -rf $DEMO_HOME/raft-vault_4
  mkdir -pm 0755 $DEMO_HOME/raft-vault_4

  tee $DEMO_HOME/config-vault_4.hcl 1> /dev/null <<EOF
  storage "raft" {
    path    = "$DEMO_HOME/raft-vault_4/"
    node_id = "vault_4"
  }
  listener "tcp" {
    address = "127.0.0.4:8200"
    cluster_address = "127.0.0.4:8201"
    tls_disable = true
  }
  seal "transit" {
    address            = "http://127.0.0.1:8200"
    # token is read from VAULT_TOKEN env
    # token              = ""
    disable_renewal    = "false"

    // Key configuration
    key_name           = "unseal_key"
    mount_path         = "transit/"
  }
  disable_mlock = true
  cluster_addr = "http://127.0.0.4:8201"
EOF
}

function setup_vault_1 {

  printf "\n%s" \
    "[vault_1] starting Vault server @ http://127.0.0.1:8200" \
    ""

  VAULT_API_ADDR=http://127.0.0.1:8200 vault server -log-level=trace -config $DEMO_HOME/config-vault_1.hcl > $DEMO_HOME/vault_1.log 2>&1 &
  sleep 5s

  printf "\n%s" \
    "[vault_1] initializing and capturing the unseal key and root token" \
    ""
  sleep 2s # Added for human readability

  INIT_RESPONSE=$(vault_1 operator init -format=json -key-shares 1 -key-threshold 1)

  UNSEAL_KEY=$(echo $INIT_RESPONSE | jq -r .unseal_keys_b64[0])
  VAULT_TOKEN=$(echo $INIT_RESPONSE | jq -r .root_token)

  echo $UNSEAL_KEY > unseal_key-vault_1
  echo $VAULT_TOKEN > root_token-vault_1

  printf "\n%s" \
    "[vault_1] Unseal key: $UNSEAL_KEY" \
    "[vault_1] Root token: $VAULT_TOKEN" \
    ""

  printf "\n%s" \
    "[vault_1] unsealing and logging in" \
    ""
  sleep 2s # Added for human readability

  vault_1 operator unseal $UNSEAL_KEY
  vault_1 login $VAULT_TOKEN

  printf "\n%s" \
    "[vault_1] enabling the transit secret engine and creating a key to auto-unseal vault_2" \
    ""
  sleep 5s # Added for human readability

  vault_1 secrets enable transit
  vault_1 write -f transit/keys/unseal_key
}

function setup_vault_2 {

  if [[ -e "$DEMO_HOME/root_token-vault_1" ]] ; then
    VAULT_TOKEN=$(cat $DEMO_HOME/root_token-vault_1)

    printf "\n%s" \
      "Using [vault_1] root token ($VAULT_TOKEN) to retrieve transit key for auto-unseal"
  fi

  printf "\n%s" \
    "[vault_2] starting Vault server @ http://127.0.0.2:8200" \
    ""
  sleep 2s # Added for human readability

  VAULT_TOKEN=$VAULT_TOKEN VAULT_API_ADDR=http://127.0.0.2:8200 vault server -log-level=trace -config $DEMO_HOME/config-vault_2.hcl > $DEMO_HOME/vault_2.log 2>&1 &

  sleep 5s

  printf "\n%s" \
    "[vault_2] initializing and capturing the recovery key and root token" \
    ""
  sleep 2s # Added for human readability

  # Initialize the second node and capture its recovery keys and root token
  INIT_RESPONSE2=$(vault_2 operator init -format=json -recovery-shares 1 -recovery-threshold 1)

  RECOVERY_KEY2=$(echo $INIT_RESPONSE2 | jq -r .recovery_keys_b64[0])
  VAULT_TOKEN2=$(echo $INIT_RESPONSE2 | jq -r .root_token)

  echo $RECOVERY_KEY2 > recovery_key-vault_2
  echo $VAULT_TOKEN2 > root_token-vault_2

  printf "\n%s" \
    "[vault_2] Recovery key: $RECOVERY_KEY2" \
    "[vault_2] Root token: $VAULT_TOKEN2" \
    ""

  printf "\n%s" \
    "[vault_2] waiting to join Vault cluster (15 seconds)" \
    ""

  sleep 15s

  printf "\n%s" \
    "[vault_2] logging in and enabling the KV secrets engine" \
    ""
  sleep 2s # Added for human readability

  vault_2 login $VAULT_TOKEN2
  vault_2 secrets enable -path=kv kv-v2
  sleep 2s

  printf "\n%s" \
    "[vault_2] storing secret 'kv/apikey' to demonstrate snapshot and recovery methods" \
    ""
  sleep 2s # Added for human readability

  vault_2 kv put kv/apikey webapp=ABB39KKPTWOR832JGNLS02
  vault_2 kv get kv/apikey
}

function setup_vault_3 {

  if [[ -e "$DEMO_HOME/root_token-vault_1" ]] ; then
    VAULT_TOKEN=$(cat $DEMO_HOME/root_token-vault_1)

    printf "\n%s" \
      "Using [vault_1] root token ($VAULT_TOKEN) to retrieve transit key for auto-unseal"
  fi

  printf "\n%s" \
    "[vault_3] starting Vault server @ http://127.0.0.3:8200" \
    ""
  sleep 2s # Added for human readability

  VAULT_TOKEN=$VAULT_TOKEN VAULT_API_ADDR=http://127.0.0.3:8200 vault server -log-level=trace -config $DEMO_HOME/config-vault_3.hcl > $DEMO_HOME/vault_3.log 2>&1 &
}

function setup_vault_4 {

  if [[ -e "$DEMO_HOME/root_token-vault_1" ]] ; then
    VAULT_TOKEN=$(cat $DEMO_HOME/root_token-vault_1)

    printf "\n%s" \
      "Using [vault_1] root token ($VAULT_TOKEN) to retrieve transit key for auto-unseal"

  fi

  printf "\n%s" \
    "[vault_4] starting Vault server @ http://127.0.0.4:8200" \
    ""
  sleep 2s # Added for human readability

  VAULT_TOKEN=$VAULT_TOKEN VAULT_API_ADDR=http://127.0.0.4:8200 vault server -log-level=trace -config $DEMO_HOME/config-vault_4.hcl > $DEMO_HOME/vault_4.log 2>&1 &
}

function create {
  case "$1" in
    network)
      shift ;
      create_network $@
      ;;
    config)
      shift ;
      create_config $@
      ;;
    *)
      printf "\n%s" \
      "Creates resources for the cluster." \
      "Usage: $script_name create [network|config]" \
      ""
      ;;
  esac
}

function setup {
  case "$1" in
    vault_1)
      setup_vault_1
      ;;
    vault_2)
      setup_vault_2
      ;;
    vault_3)
      setup_vault_3
      ;;
    vault_4)
      setup_vault_4
      ;;
    *)
      printf "\n%s" \
      "Sets up resources for the cluster" \
      "Usage: $script_name setup [vault_1|vault_2|vault_3|vault_4]" \
      ""
      ;;
  esac
}

case "$1" in
  create)
    shift ;
    create $@
    ;;
  setup)
    shift ;
    setup $@
    ;;
  vault_1)
    shift ;
    vault_1 $@
    ;;
  vault_2)
    shift ;
    vault_2 $@
    ;;
  vault_3)
    shift ;
    vault_3 $@
    ;;
  vault_4)
    shift ;
    vault_4 $@
    ;;
  status)
    status
    ;;
  stop)
    shift ;
    stop $@
    ;;
  clean)
    stop
    clean
    ;;
  *)
    printf "\n%s" \
      "This script helps manages a Vault HA cluster with raft storage." \
      "View the README.md the complete guide at https://learn.hashicorp.com/vault/beta/raft-storage" \
      "" \
      "Usage: $script_name [create|setup|status|stop|clean|vault_1|vault_2|vault_3|vault_4]" \
      ""
    ;;
esac
