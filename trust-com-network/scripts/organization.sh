function org_command_group() {
  # set -x

  COMMAND=$1
  shift

  if [ "${COMMAND}" == "generate-org-config" ]; then
    log "Generating new org config \"${CHANNEL_NAME}\":"
    local org=$1
    generate_org_config "${org}" 
    log "🏁 - Org config is ready."

  elif [ "${COMMAND}" == "generate-update-config-add-new-org" ]; then
    log "Generating org update config \"${CHANNEL_NAME}\":"
    local org=$1
    generate_update_config_add_new_org "${org}" 
    log "🏁 - Org config is ready."

  else
    print_help
    exit 1
  fi
}

function generate_org_config() {
  push_fn "Generatong new org config"
  local ORG_NAME=$1
  local CA_CERT=${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/peerOrganizations/${ORG_NAME}/msp/cacerts/ca-signcert.pem
  local TLS_CA_CERT=${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/peerOrganizations/${ORG_NAME}/msp/tlscacerts/tlsca-signcert.pem
  local BASE64_CA_CERT=$(base64 -w 0 "$CA_CERT")
  local BASE64_TLS_CA_CERT=$(base64 -w 0 "$TLS_CA_CERT")
  cp templates/template_new_org.json ${TEMP_DIR}/${CHANNEL_NAME}/${ORG_NAME}-org.json
  sed \
        -e "s/{{ORG_NAME}}/${ORG_NAME}/g" \
        -e "s/{{CA_CERT}}/${BASE64_CA_CERT}/g" \
        -e "s/{{TLS_ROOT_CERT}}/${BASE64_TLS_CA_CERT}/g" \
        templates/template_new_org.json \
        > "${TEMP_DIR}/${CHANNEL_NAME}/${ORG_NAME}-org.json"
  pop_fn
}

function generate_update_config_add_new_org() {
  push_fn "Generatong  config new org"
  local ORG_NAME=$1
  rm -rf {TEMP_DIR}/${CHANNEL_NAME}/modified_config.json
  jq '.channel_group.groups.Application.groups += input' ${TEMP_DIR}/${CHANNEL_NAME}/channel_config.json ${TEMP_DIR}/${CHANNEL_NAME}/${ORG_NAME}-org.json > ${TEMP_DIR}/${CHANNEL_NAME}/modified_config.json
  pop_fn
}